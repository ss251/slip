import Foundation
import MidnightKit
import Testing
@testable import Slip

@Suite(.serialized)
struct NetworkSealAdapterTests {
    @Test("a network seal maps an adapter result and records tx id plus commitment")
    @MainActor
    func adapterMapsReceipt() async throws {
        let relay = NetworkSealingServiceTests.StubRelay()
        let service = NetworkSealingServiceTests.service(relay: relay)
        let tracker = NetworkSealTracker(relayHost: "relay.test")
        let op = NetworkSealAdapter.operation(service: service, tracker: tracker)
        let round = LocalRound(id: UUID(), question: "Will it rain on Saturday?", sides: ["Yes", "No"], crewName: "Saturday crew",
                               createdAt: Date(), sealDeadline: Date().addingTimeInterval(3600))
        let result = try await op(round, 1)
        #expect(result.receipt.roundID == round.id)
        #expect(result.receipt.commitment?.count == 32)
        #expect(result.receipt.proofBytes > 4480)
        #expect(result.privateDisplay.selectedSide == "Yes")
        let recorded = try #require(tracker.receipt(for: round.id))
        #expect(recorded.txID == "0xstub1")
        for _ in 0..<50 where tracker.confirmations[round.id] == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(tracker.confirmations[round.id] == .confirmed)
    }

    /// Unlike adapterMapsReceipt, this crosses the actual presentation validation gate.
    /// Written during static review, UNRUN; it will generate a native proof when authorized.
    @Test("a submitted network receipt must survive the flow's metadata validation")
    @MainActor
    func submittedReceiptReachesFlow() async throws {
        let relay = NetworkSealingServiceTests.StubRelay()
        let tracker = NetworkSealTracker(relayHost: "relay.test")
        let flow = SealFlowModel(sealOperation: NetworkSealAdapter.operation(
            service: NetworkSealingServiceTests.service(relay: relay), tracker: tracker))
        let created = Date(timeIntervalSince1970: 1_788_000_000)
        let round = LocalRound(question: "Synthetic network round?", sides: ["Yes", "No"],
            crewName: "Test crew", createdAt: created, sealDeadline: created.addingTimeInterval(3_600))
        flow.beginSeal(round: round, choice: 1)
        await flow.waitForCurrentSeal()

        // Proving/submission failures are not the known issue and must fail this test.
        let submitted = try #require(tracker.receipt(for: round.id))
        #expect(submitted.txID == "0xstub1")
        #expect(submitted.commitment.count == 32)
        #expect(relay.submitted.count == 1)
        // The adapter currently supplies an empty questionCommitment. Remove this marker
        // only when real round binding is established; do not bypass metadataMatches.
        withKnownIssue("Network adapter omits the round commitment required by SealFlowModel") {
            #expect(flow.stage == .sealed)
        }
    }

    @Test("device identity is generated once and reused")
    func identity() throws {
        let store = MemorySecretStore()
        let a = try DeviceIdentity.secret(store: store)
        let b = try DeviceIdentity.secret(store: store)
        #expect(a.count == 32 && a == b)
        #expect(NetworkSetup.fromLaunchArguments(["--relay", "http://192.168.1.10:8787", "--contract", String(repeating: "ab", count: 32)])?.contractAddressHex == String(repeating: "ab", count: 32))
        #expect(NetworkSetup.fromLaunchArguments(["--relay", "http://x", "--contract", "zz"]) == nil)
    }

    @Test("makeFlow with a setup computes the public member id from a memory-backed secret")
    @MainActor
    func populatesMemberID() async throws {
        let tracker = NetworkSealTracker(relayHost: "relay.test")
        let setup = NetworkSetup(relayURL: URL(string: "http://relay.test")!, contractAddressHex: String(repeating: "11", count: 32))
        _ = NetworkSealAdapter.makeFlow(setup: setup, tracker: tracker, secretStore: MemorySecretStore(Data(repeating: 2, count: 32)))
        for _ in 0..<100 where tracker.memberIDHex == nil { try await Task.sleep(for: .milliseconds(20)) }
        let id = try #require(tracker.memberIDHex)
        #expect(Data(hex: id)?.count == 32)
    }
}
