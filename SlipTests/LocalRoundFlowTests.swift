import Foundation
import Testing
@testable import Slip

@Suite(.serialized)
@MainActor
struct LocalRoundFlowTests {
    @Test("a completed local step is bound to the sealed round")
    func realRoundIdentityRequired() async {
        let round = Self.round()
        let other = Self.round()
        let flow = SealFlowModel(sealOperation: Self.seal, roundOperation: { _, _ in
            Self.state(other, stage: .revealed)
        })
        flow.beginSeal(round: round, choice: 1)
        await flow.waitForCurrentSeal()
        flow.beginReveal(roundID: round.id)
        await flow.waitForCurrentRoundAction()
        #expect(flow.roundFailure == .unexpected)
        #expect(flow.roundResult == nil)
        #expect(!flow.isRoundBusy)
    }

    @Test("departing suppresses a late local result without claiming native cancellation")
    func departureSuppressesLateResult() async throws {
        let round = Self.round()
        let flow = SealFlowModel(sealOperation: Self.seal, roundOperation: { _, _ in
            try? await Task.sleep(for: .milliseconds(40))
            return Self.state(round, stage: .revealed)
        })
        flow.beginSeal(round: round, choice: 1)
        await flow.waitForCurrentSeal()
        flow.beginReveal(roundID: round.id)
        #expect(flow.isRoundBusy)
        flow.depart(roundID: round.id)
        try await Task.sleep(for: .milliseconds(60))
        #expect(!flow.isRoundBusy)
        #expect(flow.roundResult == nil)
        #expect(flow.roundFailure == nil)
    }

    @Test("a proof completion for the wrong step cannot advance presentation")
    func wrongStageIsRejected() async {
        let round = Self.round()
        let flow = SealFlowModel(sealOperation: Self.seal, roundOperation: { _, _ in
            Self.state(round, stage: .settled)
        })
        flow.beginSeal(round: round, choice: 1)
        await flow.waitForCurrentSeal()
        flow.beginReveal(roundID: round.id)
        await flow.waitForCurrentRoundAction()
        #expect(flow.roundFailure == .unexpected)
        #expect(flow.roundResult == nil)
    }

    @Test("round actions retain safe errors and cannot start from another slip")
    func safeFailureAndWrongRound() async {
        let round = Self.round()
        let flow = SealFlowModel(sealOperation: Self.seal, roundOperation: { _, _ in
            throw AppSealError.revealMismatch
        })
        flow.beginSeal(round: round, choice: 1)
        await flow.waitForCurrentSeal()
        flow.beginReveal(roundID: UUID())
        #expect(!flow.isRoundBusy)
        #expect(flow.roundFailure == .unexpected)
        flow.beginReveal(roundID: round.id)
        await flow.waitForCurrentRoundAction()
        #expect(flow.roundFailure == .revealMismatch)
        #expect(flow.roundResult == nil)
    }

    private nonisolated static func round() -> LocalRound {
        LocalRound(question: "Synthetic round?", sides: ["Yes", "No"], crewName: "Local sample")
    }

    private nonisolated static func state(_ round: LocalRound, stage: LocalRoundStage) -> LocalRoundResult {
        LocalRoundResult(roundID: round.id, round: round, stage: stage,
                         revealedChoice: 1, outcome: nil, tallyYes: 1, tallyNo: 0,
                         disputedBy: nil, steps: [])
    }

    private nonisolated static func seal(_ round: LocalRound, _ choice: UInt8) async throws -> LocalSealResult {
        LocalSealResult(receipt: LocalSealReceipt(
            roundID: round.id, questionCommitment: round.questionCommitment,
            proofData: Data([1]), proofBytes: 1, executeDuration: .milliseconds(1),
            keyLoadDuration: .milliseconds(1), proveDuration: .milliseconds(1), commitment: nil
        ), privateDisplay: LocalSealedDisplay(
            roundID: round.id, question: round.question, sides: round.sides,
            crewName: round.crewName, sealDeadline: round.sealDeadline,
            selectedSideIndex: choice == 1 ? 0 : 1,
            selectedSide: choice == 1 ? "Yes" : "No", sealedAt: round.createdAt
        ))
    }
}
