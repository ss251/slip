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
        return HTTPStewardRelay(baseURL: URL(string: "http://relay.test")!, authToken: "s3cret", session: URLSession(configuration: config))
    }

    @Test("context decodes hex state and seconds block time")
    func context() async throws {
        Stub.handler = { req in
            #expect(req.url?.path == "/context/" + String(repeating: "11", count: 32))
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer s3cret")
            return (200, Data(#"{"address":"\#(String(repeating: "11", count: 32))","stateHex":"0a0b0c","blockTimeSecs":1788000600}"#.utf8))
        }
        let ctx = try await Self.relay().context(for: String(repeating: "11", count: 32))
        #expect(ctx.contractState == Data([0x0a, 0x0b, 0x0c]))
        #expect(ctx.blockTime == 1_788_000_600)
    }

    /// The relay's `address` is carried into a JavaScript string literal alongside the
    /// device secret and the pick. A relay that answers with a quote, the wrong contract,
    /// or anything but 64 lowercase hex characters is refused here, before any of that.
    @Test("a relay may not answer with a quoted, mismatched or non-hex contract address")
    func contextRejectsHostileAddress() async throws {
        let asked = String(repeating: "11", count: 32)
        let hostile = [
            #"aa'; throw new Error('x'); //"#,          // script injection
            String(repeating: "22", count: 32),          // valid hex, but not the contract we asked for
            String(repeating: "11", count: 31),          // too short
            String(repeating: "11", count: 32) + "1",    // too long
            String(repeating: "zz", count: 32),          // not hex
            String(repeating: "１", count: 64),           // full-width digits: isHexDigit says yes, we say no
            ""
        ]
        for address in hostile {
            Stub.handler = { _ in (200, Data(#"{"address":"\#(address)","stateHex":"0a0b0c","blockTimeSecs":1788000600}"#.utf8)) }
            await #expect(throws: RelayError.malformedResponse("address"), "address \(address) should be refused") {
                _ = try await Self.relay().context(for: asked)
            }
        }
    }

    /// An uppercase answer is the same contract, so it is accepted and normalised rather
    /// than refused — the rule is about the character set reaching JavaScript, not casing.
    @Test("an uppercase address is normalised, not rejected")
    func contextNormalisesCase() async throws {
        let asked = String(repeating: "ab", count: 32)
        Stub.handler = { _ in (200, Data(#"{"address":"\#(asked.uppercased())","stateHex":"0a0b0c","blockTimeSecs":1788000600}"#.utf8)) }
        let ctx = try await Self.relay().context(for: asked)
        #expect(ctx.contractAddressHex == asked)
    }

    @Test("submit posts the raw proved transaction and returns the tx id")
    func submit() async throws {
        Stub.handler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer s3cret")
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

    final class TimeoutStub: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)) }
        override func stopLoading() {}
    }

    @Test("a timed-out submit returns a pending receipt instead of throwing")
    func submitTimesOutToPending() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TimeoutStub.self]
        let relay = HTTPStewardRelay(baseURL: URL(string: "http://relay.test")!, authToken: "t", session: URLSession(configuration: config))
        let receipt = try await relay.submit(provedTransaction: Data([1, 2, 3]))
        #expect(receipt.pending)
        #expect(receipt.txID.isEmpty)
    }
}
