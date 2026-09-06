import Foundation
import Testing
@testable import Slip

@Suite(.serialized)
@MainActor
struct SealFlowCoverageTests {
    @Test("seal errors expose only safe categories and choosing again clears the failure")
    func sealFailureRecovery() async {
        let round = Self.round()
        let errors: [any Error & Sendable] = [AppSealError.cancelled, SyntheticFailure(), CancellationError()]
        let expected: [AppSealError] = [.cancelled, .unexpected, .unexpected]

        for (error, safeError) in zip(errors, expected) {
            let flow = SealFlowModel { _, _ in throw error }
            flow.beginSeal(round: round, choice: 1)
            await flow.waitForCurrentSeal()

            #expect(flow.stage == .failed)
            #expect(flow.failure == safeError)
            let failedWithoutPrivateResult = flow.result == nil
            #expect(failedWithoutPrivateResult)
            flow.chooseAgain()
            #expect(flow.stage == .choosing)
            #expect(flow.failure == nil)
            #expect(!flow.consumeSealFeedback(roundID: round.id))
        }
    }

    @Test("revisiting a sealed round reuses its original result without proving again")
    func cachedPresentationIsAuthoritative() async {
        let round = Self.round()
        let calls = FlowCallLog()
        let flow = SealFlowModel { round, choice in
            await calls.recordSeal()
            return Self.seal(round, choice)
        }
        flow.beginSeal(round: round, choice: 1)
        await flow.waitForCurrentSeal()
        #expect(flow.consumeSealFeedback(roundID: round.id))
        let original = flow.result
        flow.depart(roundID: round.id)
        flow.beginSeal(round: round, choice: 0)
        flow.chooseAgain()

        #expect(flow.stage == .sealed)
        #expect(flow.activeRoundID == round.id)
        #expect(flow.failure == nil)
        let originalWasRetained = flow.result == original
        #expect(originalWasRetained)
        #expect(!flow.consumeSealFeedback(roundID: round.id))
        #expect(await calls.sealCount == 1)
    }

    @Test("seal readback is accepted only when it belongs to the immutable round")
    func readbackUsesMatchingMetadata() async {
        let round = Self.round()
        let other = Self.round()
        for readback in [Self.state(round, stage: .sealed), Self.state(other, stage: .sealed)] {
            let flow = SealFlowModel(
                sealOperation: { Self.seal($0, $1) },
                roundOperation: { _, _ in throw AppSealError.unexpected },
                readRound: { _ in readback }
            )
            flow.beginSeal(round: round, choice: 1)
            await flow.waitForCurrentSeal()

            #expect(flow.stage == .sealed)
            #expect(flow.failure == nil)
            #expect(flow.roundResult == (readback.round == round ? readback : nil))
        }
    }

    @Test("reveal then settle then dispute publishes only the completed matching step")
    func successfulRoundTransitions() async {
        let round = Self.round()
        let calls = FlowCallLog()
        let flow = SealFlowModel(sealOperation: { Self.seal($0, $1) }, roundOperation: { _, action in
            switch action {
            case .reveal:
                await calls.recordAction("reveal")
                return Self.state(round, stage: .revealed)
            case .settle(let outcome):
                await calls.recordAction("settle", outcome: outcome)
                return Self.state(round, stage: .settled, outcome: outcome)
            case .dispute:
                await calls.recordAction("dispute")
                return Self.state(round, stage: .disputed, outcome: 3)
            }
        })
        flow.beginSeal(round: round, choice: 1)
        await flow.waitForCurrentSeal()
        flow.beginReveal(roundID: round.id)
        await flow.waitForCurrentRoundAction()
        #expect(flow.roundResult?.stage == .revealed)
        #expect(!flow.isRoundBusy)
        flow.beginSettle(roundID: round.id, outcome: 0)
        await flow.waitForCurrentRoundAction()
        #expect(flow.roundResult?.stage == .settled)
        #expect(flow.roundResult?.outcome == 0)
        flow.beginDispute(roundID: round.id)
        await flow.waitForCurrentRoundAction()

        #expect(flow.roundResult?.stage == .disputed)
        #expect(flow.roundResult?.outcome == 3)
        #expect(flow.roundFailure == nil)
        #expect(!flow.isRoundBusy)
        #expect(await calls.actions == ["reveal", "settle", "dispute"])
        #expect(await calls.outcomes == [0])
    }

    @Test("an unknown round-operation failure is sanitized and a retry can complete")
    func roundFailureCanRecover() async {
        let round = Self.round()
        let calls = FlowCallLog()
        let flow = SealFlowModel(sealOperation: { Self.seal($0, $1) }, roundOperation: { _, _ in
            let attempt = await calls.recordAction("reveal")
            if attempt == 1 { throw SyntheticFailure() }
            return Self.state(round, stage: .revealed)
        })
        flow.beginSeal(round: round, choice: 1)
        await flow.waitForCurrentSeal()
        flow.beginReveal(roundID: round.id)
        await flow.waitForCurrentRoundAction()
        #expect(flow.roundFailure == .unexpected)
        #expect(flow.roundResult == nil)
        #expect(!flow.isRoundBusy)

        flow.beginReveal(roundID: round.id)
        #expect(flow.roundFailure == nil)
        #expect(flow.isRoundBusy)
        await flow.waitForCurrentRoundAction()
        #expect(flow.roundResult?.stage == .revealed)
        #expect(flow.roundFailure == nil)
        #expect(!flow.isRoundBusy)
    }

    @Test("a busy proof rejects concurrent seal and round actions without replacing its identity")
    func busyOperationsCannotOverlap() async {
        let round = Self.round()
        let other = Self.round()
        let sealGate = FlowOperationGate()
        let roundGate = FlowOperationGate()
        let flow = SealFlowModel(sealOperation: { round, choice in
            await sealGate.suspend()
            return Self.seal(round, choice)
        }, roundOperation: { _, _ in
            await roundGate.suspend()
            return Self.state(round, stage: .revealed)
        })

        flow.beginSeal(round: round, choice: 1)
        await sealGate.waitUntilStarted()
        flow.beginSeal(round: other, choice: 0)
        flow.beginReveal(roundID: round.id)
        #expect(flow.stage == .proving)
        #expect(flow.activeRoundID == round.id)
        #expect(flow.roundFailure == nil)
        #expect(!flow.isRoundBusy)
        await sealGate.release()
        await flow.waitForCurrentSeal()

        flow.beginReveal(roundID: round.id)
        await roundGate.waitUntilStarted()
        flow.beginSettle(roundID: round.id, outcome: 0)
        flow.beginSeal(round: other, choice: 0)
        #expect(flow.activeRoundID == round.id)
        #expect(flow.isRoundBusy)
        #expect(flow.roundResult == nil)
        await roundGate.release()
        await flow.waitForCurrentRoundAction()
        #expect(flow.roundResult?.stage == .revealed)
        #expect(!flow.isRoundBusy)
        #expect(await sealGate.startCount == 1)
        #expect(await roundGate.startCount == 1)
    }

    private nonisolated static func round() -> LocalRound {
        LocalRound(question: "Synthetic coverage round?", sides: ["Yes", "No"], crewName: "Local sample")
    }

    private nonisolated static func state(
        _ round: LocalRound, stage: LocalRoundStage, outcome: UInt8? = nil
    ) -> LocalRoundResult {
        LocalRoundResult(roundID: round.id, round: round, stage: stage,
                         revealedChoice: stage == .sealed ? nil : 1, outcome: outcome,
                         tallyYes: stage == .sealed ? 0 : 1, tallyNo: 0,
                         disputedBy: nil, steps: [])
    }

    private nonisolated static func seal(_ round: LocalRound, _ choice: UInt8) -> LocalSealResult {
        let index = choice == 1 ? 0 : 1
        return LocalSealResult(receipt: LocalSealReceipt(
            roundID: round.id, questionCommitment: round.questionCommitment,
            proofData: Data([1]), proofBytes: 1, executeDuration: .milliseconds(1),
            keyLoadDuration: .milliseconds(1), proveDuration: .milliseconds(1), commitment: nil
        ), privateDisplay: LocalSealedDisplay(
            roundID: round.id, question: round.question, sides: round.sides,
            crewName: round.crewName, sealDeadline: round.sealDeadline,
            selectedSideIndex: index, selectedSide: round.sides[index], sealedAt: round.createdAt
        ))
    }
}

private struct SyntheticFailure: Error, Sendable {}

private actor FlowCallLog {
    private(set) var sealCount = 0
    private(set) var actions: [String] = []
    private(set) var outcomes: [UInt8] = []

    func recordSeal() { sealCount += 1 }

    @discardableResult
    func recordAction(_ action: String, outcome: UInt8? = nil) -> Int {
        actions.append(action)
        if let outcome { outcomes.append(outcome) }
        return actions.count
    }
}

/// Holds an injected operation until the test has inspected its in-flight state.
/// The continuation models native work without timing assumptions or sleeps.
private actor FlowOperationGate {
    private(set) var startCount = 0
    private var released = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        startCount += 1
        guard !released else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
        }
    }

    func waitUntilStarted() async {
        guard startCount == 0 else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        released = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }
}
