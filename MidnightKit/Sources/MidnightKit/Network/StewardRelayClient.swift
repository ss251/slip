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
        txID = try c.decode(String.self, forKey: .txID); pending = false
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
    public init(baseURL: URL, authToken: String? = nil, session: URLSession = .shared) { self.baseURL = baseURL; self.authToken = authToken; self.session = session }

    private func authorize(_ request: inout URLRequest) {
        if let authToken { request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization") }
    }

    private struct ContextDTO: Decodable { let address: String; let stateHex: String; let blockTimeSecs: UInt64 }
    private struct ConfirmDTO: Decodable { let status: ConfirmationStatus }

    public func context(for contractAddressHex: String) async throws -> NetworkContext {
        let dto: ContextDTO = try await get("context/\(contractAddressHex)")
        guard let state = Data(hex: dto.stateHex) else { throw RelayError.malformedResponse("stateHex") }
        return NetworkContext(contractAddressHex: dto.address, contractState: state, blockTime: dto.blockTimeSecs)
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
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            // The transaction may already be on-chain; report pending and let the caller
            // resolve it through `confirm(commitmentHex:)` rather than showing a failure.
            return SubmissionReceipt(txID: "", pending: true)
        }
        try Self.check(response)
        return try JSONDecoder().decode(SubmissionReceipt.self, from: data)
    }

    public func confirm(commitmentHex: String) async throws -> ConfirmationStatus {
        let dto: ConfirmDTO = try await get("confirm/\(commitmentHex)")
        return dto.status
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        authorize(&request)
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw RelayError.badStatus(http.statusCode) }
    }
}

extension Data {
    /// Strict hex decoding (even length, 0-9a-fA-F only, optional 0x).
    public init?(hex: String) {
        let h = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard h.count % 2 == 0 else { return nil }
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
