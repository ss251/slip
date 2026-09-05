import Foundation
import MidnightKit
import Testing
@testable import Slip

@Suite(.serialized)
struct NetworkSealAdapterTests {
    @Test("a network seal renders through the existing ticket result and records tx id + commitment")
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

    @Test("device identity is generated once and reused")
    func identity() throws {
        let store = MemorySecretStore()
        let a = try DeviceIdentity.secret(store: store)
        let b = try DeviceIdentity.secret(store: store)
        #expect(a.count == 32 && a == b)
        #expect(NetworkSetup.fromLaunchArguments(["--relay", "http://192.168.1.10:8787", "--contract", String(repeating: "ab", count: 32)])?.contractAddressHex == String(repeating: "ab", count: 32))
        #expect(NetworkSetup.fromLaunchArguments(["--relay", "http://x", "--contract", "zz"]) == nil)
    }
}
