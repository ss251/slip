import Foundation
import MidnightKit
import Testing
@testable import Slip

@Suite(.serialized)
@MainActor
struct NetworkSealAdapterCoverageTests {
    @Test("an invalid side is rejected before asking the relay for public context")
    func invalidChoiceDoesNotReachRelay() async {
        let relay = AdapterRelay()
        let tracker = NetworkSealTracker()
        let operation = NetworkSealAdapter.operation(service: Self.service(relay), tracker: tracker)
        await #expect(throws: AppSealError.invalidChoice) {
            _ = try await operation(Self.round(), 2)
        }
        #expect(await relay.contextRequests == 0)
        #expect(tracker.receipts.isEmpty)
        #expect(tracker.confirmations.isEmpty)
    }

    @Test("relay transport failure reaches the caller without recording a fabricated ticket")
    func transportFailurePreservesError() async {
        let relay = AdapterRelay(contextFailure: .offline)
        let tracker = NetworkSealTracker()
        let operation = NetworkSealAdapter.operation(service: Self.service(relay), tracker: tracker)
        do {
            _ = try await operation(Self.round(), 1)
            Issue.record("An offline relay must not produce a seal result")
        } catch let error as URLError {
            #expect(error.code == .notConnectedToInternet)
        } catch {
            Issue.record("The adapter must preserve the transport error type")
        }
        #expect(await relay.contextRequests == 1)
        #expect(tracker.receipts.isEmpty)
        #expect(tracker.confirmations.isEmpty)
    }

    @Test("relay cancellation propagates without recording a seal")
    func cancellationPreservesError() async {
        let relay = AdapterRelay(contextFailure: .cancelled)
        let tracker = NetworkSealTracker()
        let operation = NetworkSealAdapter.operation(service: Self.service(relay), tracker: tracker)
        await #expect(throws: CancellationError.self) {
            _ = try await operation(Self.round(), 0)
        }
        #expect(await relay.contextRequests == 1)
        #expect(tracker.receipts.isEmpty)
        #expect(tracker.confirmations.isEmpty)
    }

    @Test("missing setup and an unavailable identity both return a usable local flow")
    func missingSetupOrIdentityFallsBackLocally() async throws {
        let setup = NetworkSetup(
            relayURL: try #require(URL(string: "http://relay.test")),
            contractAddressHex: NetworkSealingServiceTests.address
        )
        for configuration in [nil, setup] {
            let store = ReadFailureStore()
            let tracker = NetworkSealTracker()
            let flow = NetworkSealAdapter.makeFlow(setup: configuration, tracker: tracker, secretStore: store)
            #expect(store.readCount == (configuration == nil ? 0 : 1))
            #expect(flow.stage == .choosing)
            // A local validation failure proves this is an operational flow without
            // running a proof or allowing a real URLSession request.
            flow.beginSeal(round: Self.round(), choice: 2)
            await flow.waitForCurrentSeal()
            #expect(flow.stage == .failed)
            #expect(flow.failure == .invalidChoice)
            #expect(tracker.memberIDHex == nil)
            #expect(tracker.receipts.isEmpty)
        }
    }

    @Test("a failed confirmation keeps the submitted receipt and does not invent confirmed status")
    func confirmationFailureDoesNotUndoSubmission() async throws {
        let relay = AdapterRelay(failConfirmation: true)
        let tracker = NetworkSealTracker()
        let operation = NetworkSealAdapter.operation(service: Self.service(relay), tracker: tracker)
        let round = Self.round()
        let result = try await operation(round, 0)
        for _ in 0..<100 where await relay.confirmationRequests == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await relay.confirmationRequests == 1)
        await Task.yield()
        #expect(result.privateDisplay.selectedSideIndex == 1)
        #expect(result.privateDisplay.selectedSide == "No")
        #expect(tracker.receipt(for: round.id)?.txID == "synthetic-submission")
        #expect(tracker.receipt(for: round.id)?.commitment == result.receipt.commitment)
        #expect(tracker.confirmations[round.id] == nil)
    }

    private static func round() -> LocalRound {
        let created = Date(timeIntervalSince1970: 1_788_000_000)
        return LocalRound(
            question: "Synthetic coverage round?", sides: ["Yes", "No"], crewName: "Test crew",
            createdAt: created, sealDeadline: created.addingTimeInterval(3_600)
        )
    }

    private static func service(_ relay: AdapterRelay) -> NetworkSealingService {
        NetworkSealingService(
            relay: relay, prover: Prover(artifacts: LocalSealingService.bundledArtifacts()),
            contractAddressHex: NetworkSealingServiceTests.address,
            deviceSecret: Data(repeating: 2, count: 32)
        )
    }

    private actor AdapterRelay: StewardRelay {
        enum ContextFailure: Sendable { case offline, cancelled }
        let contextFailure: ContextFailure?
        let failConfirmation: Bool
        private(set) var contextRequests = 0
        private(set) var confirmationRequests = 0

        init(contextFailure: ContextFailure? = nil, failConfirmation: Bool = false) {
            self.contextFailure = contextFailure
            self.failConfirmation = failConfirmation
        }

        func context(for contractAddressHex: String) async throws -> NetworkContext {
            contextRequests += 1
            switch contextFailure {
            case .offline: throw URLError(.notConnectedToInternet)
            case .cancelled: throw CancellationError()
            case nil:
                return NetworkContext(
                    contractAddressHex: contractAddressHex,
                    contractState: NetworkSealingServiceTests.fixtureState, blockTime: 1_788_000_600
                )
            }
        }

        func submit(provedTransaction: Data) async throws -> SubmissionReceipt {
            SubmissionReceipt(txID: "synthetic-submission")
        }

        func confirm(commitmentHex: String) async throws -> ConfirmationStatus {
            confirmationRequests += 1
            if failConfirmation { throw URLError(.notConnectedToInternet) }
            return .confirmed
        }
    }

    private final class ReadFailureStore: SecretStore, @unchecked Sendable {
        private let lock = NSLock()
        private var reads = 0
        var readCount: Int {
            lock.lock(); defer { lock.unlock() }
            return reads
        }
        func read() throws -> Data? {
            lock.lock(); defer { lock.unlock() }
            reads += 1
            throw CancellationError()
        }
        func write(_ secret: Data) throws { throw CancellationError() }
    }
}
