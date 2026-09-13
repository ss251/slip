import Foundation
import MidnightKit
import Testing
@testable import Slip

/// Static-review regressions. Written during the simulator-free review; not yet run.
@Suite(.serialized)
struct RelayBoundaryReviewTests {
    @Test("a successful submit needs a nonempty transaction identifier")
    func rejectsEmptySuccessfulReceipt() throws {
        for value in ["", "   ", "\n"] {
            let data = try JSONSerialization.data(withJSONObject: ["txId": value])
            #expect(throws: RelayError.malformedResponse("txId")) {
                try JSONDecoder().decode(SubmissionReceipt.self, from: data)
            }
        }
        let valid = try JSONDecoder().decode(SubmissionReceipt.self, from: Data(#"{"txId":"0xabc"}"#.utf8))
        #expect(valid.txID == "0xabc")
        #expect(!valid.pending)
    }

    @Test("receipt identifier length matches the relay's accepted boundary")
    func boundsReceiptIdentifier() throws {
        let maximum = String(repeating: "a", count: 512)
        let valid = try JSONSerialization.data(withJSONObject: ["txId": maximum])
        #expect(try JSONDecoder().decode(SubmissionReceipt.self, from: valid).txID == maximum)
        for value in [maximum + "a", String(repeating: "😀", count: 257)] {
            let data = try JSONSerialization.data(withJSONObject: ["txId": value])
            #expect(throws: RelayError.malformedResponse("txId")) {
                try JSONDecoder().decode(SubmissionReceipt.self, from: data)
            }
        }
    }

    final class NonHTTPStub: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            #expect(request.timeoutInterval == 30)
            let response = URLResponse(url: request.url!, mimeType: "application/json",
                                       expectedContentLength: -1, textEncodingName: "utf-8")
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"status":"confirmed"}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    @Test("a non-HTTP response cannot fabricate a confirmation")
    func rejectsNonHTTPResponse() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NonHTTPStub.self]
        config.timeoutIntervalForRequest = 900
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let relay = HTTPStewardRelay(baseURL: URL(string: "https://relay.test")!, session: session)
        await #expect(throws: RelayError.malformedResponse("httpResponse")) {
            _ = try await relay.confirm(commitmentHex: String(repeating: "ab", count: 32))
        }
    }

    final class BoundedResponseStub: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let url = request.url!
            let submit = request.httpMethod == "POST"
            #expect(request.timeoutInterval == (submit ? 120 : 30))
            let scenario = url.host!
            var headers = ["Content-Type": "application/json"]
            if scenario == "oversized-header.test" {
                headers["Content-Length"] = "16777217" // above both endpoint ceilings
            }
            let response = HTTPURLResponse(url: url, statusCode: 200,
                                           httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            let json = submit ? #"{"txId":"synthetic"}"# : #"{"status":"confirmed"}"#
            var data = Data(json.utf8)
            let count = scenario == "oversized-stream.test" ? 65_537 : 65_536
            data.append(Data(repeating: 32, count: count - data.count))
            // No declared length in the streaming cases: enforcement must count bytes.
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    @Test("relay bodies are bounded with and without a declared length",
          arguments: ["oversized-header.test", "oversized-stream.test", "at-limit.test"])
    func boundsResponseBodies(_ host: String) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BoundedResponseStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let relay = HTTPStewardRelay(baseURL: URL(string: "https://\(host)")!, session: session)
        if host == "at-limit.test" {
            #expect(try await relay.confirm(commitmentHex: String(repeating: "ab", count: 32)) == .confirmed)
            let receipt = try await relay.submit(provedTransaction: Data([1]))
            #expect(receipt.txID == "synthetic")
            #expect(!receipt.pending)
        } else {
            await #expect(throws: RelayError.malformedResponse("responseSize")) {
                _ = try await relay.confirm(commitmentHex: String(repeating: "ab", count: 32))
            }
            await #expect(throws: RelayError.malformedResponse("responseSize")) {
                _ = try await relay.submit(provedTransaction: Data([1]))
            }
            if host == "oversized-header.test" {
                await #expect(throws: RelayError.malformedResponse("responseSize")) {
                    _ = try await relay.context(for: String(repeating: "ab", count: 32))
                }
            }
        }
    }

    final class RedirectStub: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard request.url?.host == "relay.test" else {
                Issue.record("The client followed a relay redirect")
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token")
            let destination = URL(string: "http://redirect-target.test/forwarded")!
            let response = HTTPURLResponse(url: request.url!, statusCode: 307,
                httpVersion: "HTTP/1.1", headerFields: ["Location": destination.absoluteString])!
            var redirected = request
            redirected.url = destination
            client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
        }
        override func stopLoading() {}
    }

    @Test("relay redirects cannot forward authenticated context, submit or confirmation requests")
    func refusesRelayRedirects() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RedirectStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let relay = HTTPStewardRelay(baseURL: URL(string: "https://relay.test")!,
            authToken: "synthetic-token", session: session)
        await #expect(throws: RelayError.badStatus(307)) {
            _ = try await relay.context(for: String(repeating: "ab", count: 32))
        }
        await #expect(throws: RelayError.badStatus(307)) {
            _ = try await relay.submit(provedTransaction: Data([1]))
        }
        await #expect(throws: RelayError.badStatus(307)) {
            _ = try await relay.confirm(commitmentHex: String(repeating: "ab", count: 32))
        }
    }

    actor InvalidTimeRelay: StewardRelay {
        let time: UInt64
        private(set) var submissions = 0
        init(time: UInt64) { self.time = time }
        func context(for contractAddressHex: String) async throws -> NetworkContext {
            // Deliberately invalid state: time must be rejected before native state loading.
            NetworkContext(contractAddressHex: contractAddressHex, contractState: Data(), blockTime: time)
        }
        func submit(provedTransaction: Data) async throws -> SubmissionReceipt {
            submissions += 1
            return SubmissionReceipt(txID: "unexpected")
        }
        func confirm(commitmentHex: String) async throws -> ConfirmationStatus { .pending }
    }

    @Test("unsafe relay times fail before native execution or submission")
    func rejectsUnsafeBlockTimes() async {
        for time in [UInt64(9_007_199_254_739_192), 9_007_199_254_740_992, UInt64.max] {
            let relay = InvalidTimeRelay(time: time)
            let service = NetworkSealingService(relay: relay,
                prover: Prover(artifacts: LocalSealingService.bundledArtifacts()),
                contractAddressHex: String(repeating: "ab", count: 32),
                deviceSecret: Data(repeating: 2, count: 32))
            await #expect(throws: NetworkSealError.invalidBlockTime) {
                _ = try await service.seal(choice: 1)
            }
            #expect(await relay.submissions == 0)
        }
    }

}
