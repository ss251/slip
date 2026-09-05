import Testing
import Foundation
@testable import MidnightKit

/// Request/response shapes of the relay contract, without a server.
@Suite(.serialized)
struct StewardRelayClientTests {
    final class Stub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let (status, body) = Stub.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    static func relay() -> HTTPStewardRelay {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        return HTTPStewardRelay(baseURL: URL(string: "http://relay.test")!, session: URLSession(configuration: config))
    }

    @Test("context decodes hex state and seconds block time")
    func context() async throws {
        Stub.handler = { req in
            #expect(req.url?.path == "/context/" + String(repeating: "11", count: 32))
            return (200, Data(#"{"address":"\#(String(repeating: "11", count: 32))","stateHex":"0a0b0c","blockTimeSecs":1788000600}"#.utf8))
        }
        let ctx = try await Self.relay().context(for: String(repeating: "11", count: 32))
        #expect(ctx.contractState == Data([0x0a, 0x0b, 0x0c]))
        #expect(ctx.blockTime == 1_788_000_600)
    }

    @Test("submit posts the raw proved transaction and returns the tx id")
    func submit() async throws {
        Stub.handler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
            return (200, Data(#"{"txId":"0xabc"}"#.utf8))
        }
        let receipt = try await Self.relay().submit(provedTransaction: Data([1, 2, 3]))
        #expect(receipt.txID == "0xabc")
    }

    @Test("non-2xx becomes a typed error; bad hex is rejected")
    func errors() async throws {
        Stub.handler = { _ in (503, Data()) }
        await #expect(throws: RelayError.badStatus(503)) { _ = try await Self.relay().confirm(commitmentHex: "00") }
        #expect(Data(hex: "0x0g") == nil)
        #expect(Data(hex: "abc") == nil)
        #expect(Data([0xde, 0xad]).hexString == "dead")
    }
}
