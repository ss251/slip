import Foundation
import MidnightKit
import Testing

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
}
