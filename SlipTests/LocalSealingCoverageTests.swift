import Foundation
import MidnightKit
import Testing
@testable import Slip

@Suite(.serialized)
struct LocalSealingCoverageTests {
    @Test("incomplete public metadata fails before artifact access")
    func incompleteMetadata() async {
        let service = LocalSealingService(artifacts: Self.artifacts(at:
            FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let rounds = [
            LocalRound(question: " \n", sides: ["Yes", "No"], crewName: "Crew"),
            LocalRound(question: "Question?", sides: ["Yes"], crewName: "Crew"),
            LocalRound(question: "Question?", sides: ["Yes", " \t"], crewName: "Crew"),
            LocalRound(question: "Question?", sides: ["Yes", "No"], crewName: " \n")
        ]
        for round in rounds {
            await #expect(throws: AppSealError.invalidRoundMetadata) {
                _ = try await service.seal(round: round, choice: 1)
            }
            #expect(await service.currentResult(roundID: round.id) == nil)
        }
    }

    @Test("a missing proving key is named before private execution")
    func missingKey() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let artifacts = Self.artifacts(at: root)
        try FileManager.default.createDirectory(at: artifacts.circuitsDirectory, withIntermediateDirectories: true)
        try Data([0]).write(to: artifacts.circuitsDirectory.appendingPathComponent("sealPick.zkir"))
        let service = LocalSealingService(artifacts: artifacts)
        let round = Self.round()
        await #expect(throws: AppSealError.provingKeyMissing) {
            _ = try await service.seal(round: round, choice: 1)
        }
        #expect(await service.currentResult(roundID: round.id) == nil)
        #expect(AppSealError.provingKeyMissing.errorDescription == "Proving key missing")
    }

    @Test("native artifact failure releases the active round and permits a clean retry")
    func nativeFailureCanRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = LocalSealingService.bundledArtifacts()
        let artifacts = Self.artifacts(at: root)
        // Only public, immutable circuit files are copied. Large keys and parameters
        // stay in the bundle; the test never writes a private preimage or a witness.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: bundled.circuitsDirectory, to: artifacts.circuitsDirectory)
        let failingCircuit = artifacts.circuitsDirectory.appendingPathComponent("enrollMember.zkir")
        try Data("invalid public circuit".utf8).write(to: failingCircuit)
        let service = LocalSealingService(artifacts: ProofArtifacts(
            circuitsDirectory: artifacts.circuitsDirectory,
            keysDirectory: bundled.keysDirectory,
            parametersDirectory: bundled.parametersDirectory))
        let round = Self.round()

        await #expect(throws: AppSealError.circuitNotFound) {
            _ = try await service.seal(round: round, choice: 1)
        }
        #expect(await service.currentResult(roundID: round.id) == nil)
        #expect(AppSealError.circuitNotFound.errorDescription == "Proof circuit unavailable")

        try FileManager.default.removeItem(at: failingCircuit)
        try FileManager.default.copyItem(
            at: bundled.circuitsDirectory.appendingPathComponent("enrollMember.zkir"), to: failingCircuit)
        let recovered = try await service.seal(round: round, choice: 1)
        #expect(recovered.receipt.roundID == round.id)
        #expect(recovered.receipt.proofBytes > 0)
        #expect(await service.currentResult(roundID: round.id)?.stage == .sealed)
    }

    @Test("lifecycle actions reject absent rounds and premature disputes without changing state")
    func invalidLifecycleTransitions() async throws {
        let service = LocalSealingService(artifacts: LocalSealingService.bundledArtifacts())
        let round = Self.round()
        await #expect(throws: AppSealError.roundNotFound) {
            _ = try await service.reveal(roundID: round.id)
        }
        await #expect(throws: AppSealError.roundNotFound) {
            _ = try await service.settle(roundID: round.id, outcome: 1)
        }
        await #expect(throws: AppSealError.roundNotFound) {
            _ = try await service.dispute(roundID: round.id)
        }
        _ = try await service.seal(round: round, choice: 1)
        let sealed = await service.currentResult(roundID: round.id)
        await #expect(throws: AppSealError.invalidRoundTransition) {
            _ = try await service.dispute(roundID: round.id)
        }
        await #expect(throws: AppSealError.invalidOutcome) {
            _ = try await service.settle(roundID: round.id, outcome: 2)
        }
        #expect(await service.currentResult(roundID: round.id) == sealed)
        let settled = try await service.settle(roundID: round.id, outcome: 0)
        #expect(settled.stage == .settled)
        #expect(settled.revealedChoice == nil)
        await #expect(throws: AppSealError.invalidRoundTransition) {
            _ = try await service.reveal(roundID: round.id)
        }
        #expect(await service.currentResult(roundID: round.id) == settled)
    }

    private static func artifacts(at root: URL) -> ProofArtifacts {
        ProofArtifacts(circuitsDirectory: root.appendingPathComponent("zkir"),
                       keysDirectory: root.appendingPathComponent("keys"),
                       parametersDirectory: root.appendingPathComponent("params"))
    }

    private static func round() -> LocalRound {
        LocalRound(question: "Does the local test recover?", sides: ["Yes", "No"], crewName: "Local tests")
    }
}
