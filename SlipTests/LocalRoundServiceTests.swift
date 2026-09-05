import Foundation
import Testing
@testable import Slip

@Suite(.serialized)
struct LocalRoundServiceTests {
    @Test(
        "each lifecycle circuit produces a real proof receipt",
        arguments: LocalProofStep.allCases
    )
    func eachLifecycleCircuitProducesARealProof(target: LocalProofStep) async throws {
        let service = Self.makeService()
        let round = Self.makeRound()

        _ = try await service.seal(round: round, choice: 1)

        let result: LocalRoundResult
        switch target {
        case .enrollMember, .createSlip, .sealPick:
            let current = await service.currentResult(roundID: round.id)
            result = try #require(current)
        case .reveal:
            result = try await service.reveal(roundID: round.id)
        case .settle:
            result = try await service.settle(roundID: round.id, outcome: 1)
        case .dispute:
            _ = try await service.settle(roundID: round.id, outcome: 1)
            result = try await service.dispute(roundID: round.id)
        }

        let receipt = try #require(result.steps.first { $0.step == target })
        #expect(receipt.proofBytes > 0)
        #expect(receipt.executeDuration > .zero)
        #expect(receipt.keyLoadDuration >= .zero)
        #expect(receipt.proveDuration > .zero)

        print(
            "LOCAL_CIRCUIT_PROOF step=\(receipt.step.rawValue) "
                + "execute_ms=\(Self.milliseconds(receipt.executeDuration)) "
                + "key_ms=\(Self.milliseconds(receipt.keyLoadDuration)) "
                + "prove_ms=\(Self.milliseconds(receipt.proveDuration)) "
                + "bytes=\(receipt.proofBytes)"
        )
    }

    @Test("the local lifecycle proves all six circuits and reads accepted ledger state")
    func realProofForEveryLifecycleCircuit() async throws {
        let service = Self.makeService()
        let round = Self.makeRound()

        _ = try await service.seal(round: round, choice: 1)
        let currentAfterSeal = await service.currentResult(roundID: round.id)
        let sealed = try #require(currentAfterSeal)
        #expect(sealed.stage == .sealed)
        #expect(sealed.revealedChoice == nil)
        #expect(sealed.outcome == nil)
        #expect(sealed.tallyYes == 0)
        #expect(sealed.tallyNo == 0)
        #expect(sealed.steps.map(\.step) == [.enrollMember, .createSlip, .sealPick])

        let revealed = try await service.reveal(roundID: round.id)
        #expect(revealed.stage == .revealed)
        #expect(revealed.revealedChoice == 1)
        #expect(revealed.tallyYes == 1)
        #expect(revealed.tallyNo == 0)
        #expect(revealed.steps.last?.step == .reveal)

        let duplicateReveal = try await service.reveal(roundID: round.id)
        #expect(duplicateReveal == revealed)

        let settled = try await service.settle(roundID: round.id, outcome: 1)
        #expect(settled.stage == .settled)
        #expect(settled.revealedChoice == 1)
        #expect(settled.outcome == 1)
        #expect(settled.tallyYes == 1)
        #expect(settled.tallyNo == 0)
        #expect(settled.steps.last?.step == .settle)

        let duplicateSettle = try await service.settle(roundID: round.id, outcome: 1)
        #expect(duplicateSettle == settled)
        await #expect(throws: AppSealError.outcomeConflict) {
            _ = try await service.settle(roundID: round.id, outcome: 0)
        }

        let disputed = try await service.dispute(roundID: round.id)
        #expect(disputed.stage == .disputed)
        #expect(disputed.revealedChoice == 1)
        #expect(disputed.outcome == 3)
        #expect(disputed.tallyYes == 1)
        #expect(disputed.tallyNo == 0)
        #expect(disputed.disputedBy?.count == 32)
        #expect(disputed.steps.map(\.step) == [
            .enrollMember, .createSlip, .sealPick, .reveal, .settle, .dispute
        ])
        #expect(disputed.steps.allSatisfy { $0.proofBytes > 0 })
        #expect(disputed.steps.allSatisfy { $0.executeDuration > .zero })
        #expect(disputed.steps.allSatisfy { $0.proveDuration > .zero })

        let duplicateDispute = try await service.dispute(roundID: round.id)
        #expect(duplicateDispute == disputed)
        let current = await service.currentResult(roundID: round.id)
        #expect(current == disputed)

        let stepNames = disputed.steps.map { $0.step.rawValue }.joined(separator: ",")
        print("LOCAL_ROUND_PROOFS count=\(disputed.steps.count) steps=\(stepNames)")
        for receipt in disputed.steps {
            print(
                "LOCAL_ROUND_PROOF step=\(receipt.step.rawValue) "
                    + "execute_ms=\(Self.milliseconds(receipt.executeDuration)) "
                    + "key_ms=\(Self.milliseconds(receipt.keyLoadDuration)) "
                    + "prove_ms=\(Self.milliseconds(receipt.proveDuration)) "
                    + "bytes=\(receipt.proofBytes)"
            )
        }
    }

    @Test("a circuit-level reveal mismatch is rejected and a clean replay recovers")
    func mismatchDoesNotCorruptAcceptedPrefix() async throws {
        let service = Self.makeService()
        let round = Self.makeRound()
        _ = try await service.seal(round: round, choice: 0)

        #if DEBUG
        await #expect(throws: AppSealError.revealMismatch) {
            try await service.rejectMismatchedReveal(roundID: round.id)
        }
        #else
        Issue.record("The adversarial mismatch seam is available only in test builds")
        #endif

        let currentAfterRejection = await service.currentResult(roundID: round.id)
        let afterRejection = try #require(currentAfterRejection)
        let rejectedStateStayedSealed = afterRejection.stage == .sealed
            && afterRejection.revealedChoice == nil
            && afterRejection.steps.map(\.step) == [.enrollMember, .createSlip, .sealPick]
        #expect(rejectedStateStayedSealed)

        let recovered = try await service.reveal(roundID: round.id)
        let acceptedOriginalOpening = recovered.stage == .revealed
            && recovered.revealedChoice == 0
            && recovered.tallyYes == 0
            && recovered.tallyNo == 1
            && recovered.steps.last?.step == .reveal
        #expect(acceptedOriginalOpening)
    }

    private static func makeService() -> LocalSealingService {
        LocalSealingService(artifacts: LocalSealingService.bundledArtifacts())
    }

    private static func makeRound() -> LocalRound {
        let createdAt = Date()
        return LocalRound(
            question: "Will the local sample resolve?",
            sides: ["Yes", "No"],
            crewName: "Local sample",
            createdAt: createdAt,
            sealDeadline: createdAt.addingTimeInterval(3_600)
        )
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.3f", milliseconds)
    }
}
