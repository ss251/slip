import Foundation

/// Public chain context a device needs to seal against a deployed contract.
public struct NetworkContext: Sendable, Equatable {
    public let contractAddressHex: String
    /// Tagged `ContractState` bytes exactly as the indexer serves them (hex-decoded).
    public let contractState: Data
    /// Ledger block time in SECONDS (the indexer reports milliseconds; the relay converts).
    public let blockTime: UInt64
    public init(contractAddressHex: String, contractState: Data, blockTime: UInt64) {
        self.contractAddressHex = contractAddressHex; self.contractState = contractState; self.blockTime = blockTime
    }
}

public struct SubmissionReceipt: Sendable, Equatable, Decodable {
    public let txID: String
    /// True when the client did not receive a txId (submit timed out) but the transaction
    /// may already have been broadcast. The commitment is then watched via `confirm`.
    public let pending: Bool
    public init(txID: String, pending: Bool = false) { self.txID = txID; self.pending = pending }
    enum CodingKeys: String, CodingKey { case txID = "txId" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        txID = try c.decode(String.self, forKey: .txID)
        // Match the trusted relay's 512-character identifier limit in UTF-16 units.
        // This bounds text retained in a receipt; it is not a response-body size limit.
        guard !txID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              txID.utf16.count <= 512 else {
            throw RelayError.malformedResponse("txId")
        }
        pending = false
    }
}

public enum ConfirmationStatus: String, Sendable, Decodable { case pending, confirmed, rejected }

/// The steward relay: balances, signs and submits proved transactions on the device's
/// behalf and answers public questions about the chain. It never sees a witness — the
/// device sends only the proved, unbalanced transaction (proof + public transcript).
public protocol StewardRelay: Sendable {
    func context(for contractAddressHex: String) async throws -> NetworkContext
    func submit(provedTransaction: Data) async throws -> SubmissionReceipt
    func confirm(commitmentHex: String) async throws -> ConfirmationStatus
}

public enum RelayError: Error, Equatable, Sendable {
    case badStatus(Int)
    case malformedResponse(String)
}

/// HTTP client for `scripts/steward-relay.mjs`.
public struct HTTPStewardRelay: StewardRelay {
    public let baseURL: URL
    private let session: URLSession
    /// Bearer token the relay requires; sent on every request, never logged.
    private let authToken: String?
    // Public context includes hex-encoded contract state; receipts/status are tiny JSON.
    // Transport ceilings, not promises about the maximum supported on-chain crew size.
    private static let maximumContextBytes = 16 * 1_024 * 1_024
    private static let maximumReceiptBytes = 64 * 1_024
    private static let redirectPolicy = RelayRedirectPolicy()
    private static let defaultSession = makeDefaultSession(configuration: .default)

    /// Internal factory lets regression tests use the production timeout policy with
    /// a protocol-scoped fixture instead of globally intercepting the shared session.
    static func makeDefaultSession(configuration: URLSessionConfiguration) -> URLSession {
        // Request timeouts reset when bytes arrive. Bound the entire transfer too,
        // so a drip-fed response cannot keep the default client occupied for days.
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration)
    }

    /// Supplied sessions retain their delegate and resource-timeout policy. The default
    /// session caps the entire transfer at 120 seconds, including a slowly delivered body.
    public init(baseURL: URL, authToken: String? = nil, session: URLSession? = nil) {
        self.baseURL = baseURL; self.authToken = authToken
        self.session = session ?? Self.defaultSession
    }

    private func authorize(_ request: inout URLRequest) {
        if let authToken { request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization") }
    }

    private struct ContextDTO: Decodable { let address: String; let stateHex: String; let blockTimeSecs: UInt64 }
    private struct ConfirmDTO: Decodable { let status: ConfirmationStatus }

    /// The relay is not trusted with the shape of what it returns. `address` is carried into
    /// a JavaScript string literal in the sealing driver — in the same scope as the device
    /// secret and the pick — so a quote-bearing address would be script injection with the
    /// witness in reach. It must be 64 lowercase hex characters, and it must be the contract
    /// we asked about: a relay may not silently redirect a seal at a different contract.
    public func context(for contractAddressHex: String) async throws -> NetworkContext {
        let dto: ContextDTO = try await get("context/\(contractAddressHex)", maximumBytes: Self.maximumContextBytes)
        // ASCII explicitly: `Character.isHexDigit` also accepts full-width forms, which are
        // not what we mean by hex and not what the JavaScript literal should ever receive.
        let address = dto.address.lowercased()
        guard address.utf8.count == 64,
              address.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              address == contractAddressHex.lowercased()
        else { throw RelayError.malformedResponse("address") }
        guard let state = Data(hex: dto.stateHex) else { throw RelayError.malformedResponse("stateHex") }
        return NetworkContext(contractAddressHex: address, contractState: state, blockTime: dto.blockTimeSecs)
    }

    public func submit(provedTransaction: Data) async throws -> SubmissionReceipt {
        var request = URLRequest(url: baseURL.appendingPathComponent("submit"))
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = provedTransaction
        // Balancing + signing precede the relay's response even though it now returns at
        // node acceptance; give that room so a slow-but-successful submit is not cut off.
        request.timeoutInterval = 120
        authorize(&request)
        let data: Data
        do {
            data = try await boundedData(for: request, maximumBytes: Self.maximumReceiptBytes)
        } catch let error as URLError where error.code == .timedOut {
            // The transaction may already be on-chain; report pending and let the caller
            // resolve it through `confirm(commitmentHex:)` rather than showing a failure.
            return SubmissionReceipt(txID: "", pending: true)
        }
        return try JSONDecoder().decode(SubmissionReceipt.self, from: data)
    }

    public func confirm(commitmentHex: String) async throws -> ConfirmationStatus {
        let dto: ConfirmDTO = try await get("confirm/\(commitmentHex)", maximumBytes: Self.maximumReceiptBytes)
        return dto.status
    }

    private func get<T: Decodable>(_ path: String, maximumBytes: Int) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        // Context/confirmation reads should not inherit an injected session's timeout.
        request.timeoutInterval = 30
        authorize(&request)
        let data = try await boundedData(for: request, maximumBytes: maximumBytes)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Check headers before reading and count actual bytes even without a trustworthy
    /// Content-Length. Cancelling on every exit also stops an oversized stream early.
    private func boundedData(for request: URLRequest, maximumBytes: Int) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request, delegate: Self.redirectPolicy)
        defer { bytes.task.cancel() }
        try Self.check(response)
        guard response.expectedContentLength <= Int64(maximumBytes) else {
            throw RelayError.malformedResponse("responseSize")
        }
        return try await withTaskCancellationHandler {
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximumBytes else {
                    throw RelayError.malformedResponse("responseSize")
                }
                data.append(byte)
            }
            return data
        } onCancel: {
            bytes.task.cancel()
        }
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw RelayError.malformedResponse("httpResponse")
        }
        guard (200..<300).contains(http.statusCode) else { throw RelayError.badStatus(http.statusCode) }
    }
}

/// Relay endpoints are direct. A redirect must not move the authenticated request or
/// proved transaction to another URL (including an HTTPS-to-HTTP downgrade).
/// Only redirect callbacks are intercepted; session authentication handling remains intact.
private final class RelayRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

extension Data {
    /// Strict hex decoding (even length, 0-9a-fA-F only, optional 0x).
    public init?(hex: String) {
        let h = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        // Integer parsing accepts signs (including +f and -0); wire hex does not.
        guard h.utf8.count % 2 == 0,
              h.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0)
                  || (97...102).contains($0) }) else { return nil }
        var out = Data(capacity: h.count / 2)
        var idx = h.startIndex
        while idx < h.endIndex {
            let next = h.index(idx, offsetBy: 2)
            guard let byte = UInt8(h[idx..<next], radix: 16) else { return nil }
            out.append(byte); idx = next
        }
        self = out
    }
    public var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
