import Foundation
@testable import MidnightKit
import Testing
@testable import Slip

/// Static-review regressions. Written during the simulator-free review; not yet run.
@Suite(.serialized)
struct RelayBoundaryReviewTests {
    @Test("wire hex rejects signed numeric pairs and non-ASCII characters")
    func rejectsNonHexNumericSyntax() {
        for malformed in ["+f", "-0", "ab+1", "0x+1", "0x-0", "ａｂ", "0g", "a", " ab "] {
            #expect(Data(hex: malformed) == nil, "Non-hex wire syntax must not decode")
        }
        #expect(Data(hex: "00aBfF") == Data([0, 0xab, 0xff]))
        #expect(Data(hex: "0x00aBfF") == Data([0, 0xab, 0xff]))
        #expect(Data(hex: "") == Data())
        #expect(Data(hex: "0x") == Data())
    }

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

    final class ContextSizeStub: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let url = request.url!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            let address = url.lastPathComponent
            let json = #"{"address":"\#(address)","stateHex":"010203","blockTimeSecs":1}"#
            var data = Data(json.utf8)
            let count = 16 * 1_024 * 1_024 + (url.host == "over-context-limit.test" ? 1 : 0)
            data.append(Data(repeating: 32, count: count - data.count))
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    @Test("context streaming uses its own larger bound even without Content-Length",
          .timeLimit(.minutes(1)), arguments: ["at-context-limit.test", "over-context-limit.test"])
    func boundsActualContextStream(_ host: String) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ContextSizeStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let relay = HTTPStewardRelay(baseURL: URL(string: "https://\(host)")!, session: session)
        let address = String(repeating: "ab", count: 32)
        if host == "at-context-limit.test" {
            let context = try await relay.context(for: address)
            #expect(context.contractAddressHex == address)
            #expect(context.contractState == Data([1, 2, 3]))
            #expect(context.blockTime == 1)
        } else {
            await #expect(throws: RelayError.malformedResponse("responseSize")) {
                _ = try await relay.context(for: address)
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
            // Serve the 307 the way a real server does and let URLSession's own redirect
            // machinery run, so RelayRedirectPolicy is the thing under test. Signalling
            // wasRedirectedTo(_:) by hand instead leaves the task with no completion, and
            // it then hangs until timeoutIntervalForResource rather than failing.
            let destination = URL(string: "http://redirect-target.test/forwarded")!
            let response = HTTPURLResponse(url: request.url!, statusCode: 307,
                httpVersion: "HTTP/1.1", headerFields: ["Location": destination.absoluteString])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
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

    final class DrippingResponseStub: URLProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false
        private var worker: Task<Void, Never>?
        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.host == "slow-relay.test"
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            // URLProtocol and URLProtocolClient are not Sendable, so region isolation
            // rejects a closure that captures them even though this stub is @unchecked
            // Sendable. The stub is driven by one loading task at a time; stopLoading()
            // cancels under the same lock that publishes the worker.
            nonisolated(unsafe) let host = self
            let task = Task {
                while !Task.isCancelled {
                    host.client?.urlProtocol(host, didLoad: Data([32]))
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
            lock.withLock {
                if stopped { task.cancel() } else { worker = task }
            }
        }
        override func stopLoading() {
            lock.withLock { stopped = true; worker?.cancel(); worker = nil }
        }
    }

    /// Deliberately opt-in: this checks the real default 120-second resource budget.
    /// UNRUN during static review; it neither connects to a host nor generates a proof.
    @Test("the default relay session times out a response that keeps delivering bytes",
          .timeLimit(.minutes(3)),
          .enabled(if: ProcessInfo.processInfo.environment["SLIP_TEST_RELAY_DEADLINES"] == "1"))
    func defaultSessionBoundsDrippingResponse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DrippingResponseStub.self]
        let session = HTTPStewardRelay.makeDefaultSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let relay = HTTPStewardRelay(baseURL: URL(string: "https://slow-relay.test")!, session: session)
        let started = ContinuousClock.now
        do {
            _ = try await relay.confirm(commitmentHex: String(repeating: "ab", count: 32))
            Issue.record("A never-ending response must time out")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
            let elapsed = ContinuousClock.now - started
            // The stream delivers every second, so the 30-second idle timeout is not enough.
            #expect(elapsed >= .seconds(100))
            #expect(elapsed < .seconds(180))
        }
    }

    actor GatedContextRelay: StewardRelay {
        private var started = false
        private var startWaiters: [CheckedContinuation<Void, Never>] = []
        private var release: CheckedContinuation<Void, Never>?
        private(set) var submissions = 0
        func context(for contractAddressHex: String) async throws -> NetworkContext {
            started = true
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
            // Deliberately ignore cooperative cancellation like an already-started native call.
            await withCheckedContinuation { release = $0 }
            return NetworkContext(contractAddressHex: contractAddressHex,
                                  contractState: Data(), blockTime: 1_788_000_600)
        }
        func waitUntilStarted() async {
            guard !started else { return }
            await withCheckedContinuation { startWaiters.append($0) }
        }
        func releaseContext() { release?.resume(); release = nil }
        func submit(provedTransaction: Data) async throws -> SubmissionReceipt {
            submissions += 1
            return SubmissionReceipt(txID: "unexpected")
        }
        func confirm(commitmentHex: String) async throws -> ConfirmationStatus { .pending }
    }

    @Test("cancellation after context loading stops before private runtime execution")
    func cancelledContextDoesNotStartProof() async {
        let relay = GatedContextRelay()
        let service = NetworkSealingService(relay: relay,
            prover: Prover(artifacts: LocalSealingService.bundledArtifacts()),
            contractAddressHex: String(repeating: "ab", count: 32),
            deviceSecret: Data(repeating: 2, count: 32))
        let pending = Task { try await service.seal(choice: 1) }
        await relay.waitUntilStarted()
        pending.cancel()
        await relay.releaseContext()
        // The deliberately invalid state must never reach ContractRuntime.
        await #expect(throws: CancellationError.self) { _ = try await pending.value }
        #expect(await relay.submissions == 0)
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
