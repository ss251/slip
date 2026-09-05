import Foundation
import Testing
@testable import Slip

@Suite(.serialized)
@MainActor
struct SealFlowTests {
    @Test("round metadata and private display are captured before asynchronous proving")
    func metadataIsCapturedBeforeAwait() async {
        let model = AppModel()
        let createdAt = Date(timeIntervalSince1970: 1_788_600_000)
        let firstRound = model.startLocalRound(
            question: "Original question?",
            sides: ["Up", "Down"],
            crewName: "Original crew",
            createdAt: createdAt,
            sealDeadline: createdAt.addingTimeInterval(3_600)
        )
        let flow = SealFlowModel { round, choice in
            await Task.yield()
            return Self.stubResult(round: round, choice: choice)
        }

        flow.beginSeal(round: firstRound, choice: 1)
        let secondRound = model.startLocalRound(
            question: "Replacement question?",
            sides: ["Left", "Right"],
            crewName: "Replacement crew",
            createdAt: createdAt.addingTimeInterval(10),
            sealDeadline: createdAt.addingTimeInterval(7_200)
        )
        await flow.waitForCurrentSeal()

        let capturedPrivateDisplayMatches = flow.sealedDisplay?.roundID == firstRound.id
            && flow.sealedDisplay?.question == "Original question?"
            && flow.sealedDisplay?.sides == ["Up", "Down"]
            && flow.sealedDisplay?.crewName == "Original crew"
            && flow.sealedDisplay?.selectedSide == "Up"
        #expect(flow.stage == .sealed)
        #expect(capturedPrivateDisplayMatches)
        #expect(model.localRound.id == secondRound.id)
        #expect(!model.markLocalSeal(roundID: firstRound.id))
    }

    @Test("departing a round ignores a late proof completion")
    func departureInvalidatesCompletion() async throws {
        let round = Self.makeRound(question: "Departed question?")
        let flow = SealFlowModel { round, choice in
            // Model a native operation that finishes despite cooperative cancellation.
            try? await Task.sleep(for: .milliseconds(30))
            return Self.stubResult(round: round, choice: choice)
        }

        flow.beginSeal(round: round, choice: 0)
        #expect(flow.stage == .proving)
        flow.depart(roundID: round.id)
        try await Task.sleep(for: .milliseconds(50))

        #expect(flow.stage == .choosing)
        #expect(flow.activeRoundID == nil)
        let resultWasDiscarded = flow.result == nil
        #expect(resultWasDiscarded)
        #expect(flow.failure == nil)
    }

    @Test("a cached native seal remains authoritative after cancellation and a changed retry")
    func cachedNativeSealWinsOverLaterChoice() async {
        let round = Self.makeRound(question: "Original seal wins?")
        let cache = NativeLikeSealCache { round, choice in
            Self.stubResult(round: round, choice: choice)
        }
        let flow = SealFlowModel { round, choice in
            await cache.seal(round: round, choice: choice)
        }

        flow.beginSeal(round: round, choice: 1)
        await cache.waitUntilStarted()
        flow.depart(roundID: round.id)
        await cache.completeNativeWork()
        await cache.waitUntilCached()

        // The user now asks for the opposite side, but the actor must return the
        // already-sealed original result instead of changing the pick.
        flow.beginSeal(round: round, choice: 0)
        await flow.waitForCurrentSeal()

        let originalPrivateDisplayWasRestored = flow.sealedDisplay?.selectedSideIndex == 0
            && flow.sealedDisplay?.selectedSide == "Yes"
        #expect(flow.stage == .sealed)
        #expect(flow.failure == nil)
        #expect(originalPrivateDisplayWasRestored)
    }

    @Test("a new app round has a new identity and rejects stale completion")
    func appRoundIdentityPreventsStaleCompletion() {
        let model = AppModel()
        let first = model.startLocalRound(
            question: "First?",
            sides: ["Yes", "No"],
            crewName: "Crew",
            sealDeadline: Date().addingTimeInterval(3_600)
        )
        #expect(model.markLocalSeal(roundID: first.id))
        #expect(model.hasLocalSeal)

        let second = model.startLocalRound(
            question: "Second?",
            sides: ["Over", "Under"],
            crewName: "Crew",
            sealDeadline: Date().addingTimeInterval(7_200)
        )

        #expect(first.id != second.id)
        #expect(!model.hasLocalSeal)
        #expect(!model.markLocalSeal(roundID: first.id))
        #expect(model.markLocalSeal(roundID: second.id))
        #expect(model.sampleQuestion == "Second?")
        #expect(model.sideLabels == ["Over", "Under"])
        #expect(model.selectedSide == "Over")
    }

    @Test("success feedback is consumed once per sealed round")
    func feedbackIsConsumedOnce() async {
        let round = Self.makeRound(question: "One stamp?")
        let flow = SealFlowModel { round, choice in
            Self.stubResult(round: round, choice: choice)
        }

        #expect(!flow.consumeSealFeedback(roundID: round.id))
        flow.beginSeal(round: round, choice: 1)
        await flow.waitForCurrentSeal()

        #expect(flow.consumeSealFeedback(roundID: round.id))
        #expect(!flow.consumeSealFeedback(roundID: round.id))
        #expect(!flow.consumeSealFeedback(roundID: UUID()))
    }

    @Test("cached presentation rejects a relabelled round with the same identity")
    func cachedRoundMetadataCannotBeRelabelled() async {
        let round = Self.makeRound(question: "Original identity?")
        let flow = SealFlowModel { round, choice in
            Self.stubResult(round: round, choice: choice)
        }
        flow.beginSeal(round: round, choice: 1)
        await flow.waitForCurrentSeal()

        let relabelled = LocalRound(
            id: round.id,
            question: "Relabelled identity?",
            sides: round.sides,
            crewName: round.crewName,
            createdAt: round.createdAt,
            sealDeadline: round.sealDeadline
        )
        flow.beginSeal(round: relabelled, choice: 1)

        let staleResultWasDiscarded = flow.result == nil
        #expect(flow.stage == .failed)
        #expect(flow.failure == .roundIdentityConflict)
        #expect(staleResultWasDiscarded)
    }

    @Test("internally inconsistent private display is rejected")
    func inconsistentPrivateDisplayIsRejected() async {
        let round = Self.makeRound(question: "Consistent display?")
        let badLabelFlow = SealFlowModel { round, _ in
            Self.stubResult(round: round, selectedSideIndex: 0, selectedSide: "No")
        }
        let badIndexFlow = SealFlowModel { round, _ in
            Self.stubResult(round: round, selectedSideIndex: 2, selectedSide: "Yes")
        }

        badLabelFlow.beginSeal(round: round, choice: 1)
        await badLabelFlow.waitForCurrentSeal()
        badIndexFlow.beginSeal(round: round, choice: 1)
        await badIndexFlow.waitForCurrentSeal()

        let labelMismatchWasRejected = badLabelFlow.stage == .failed
            && badLabelFlow.failure == .unexpected
            && badLabelFlow.result == nil
        let outOfRangeIndexWasRejected = badIndexFlow.stage == .failed
            && badIndexFlow.failure == .unexpected
            && badIndexFlow.result == nil
        #expect(labelMismatchWasRejected)
        #expect(outOfRangeIndexWasRejected)
    }

    @Test("a mismatched operation result fails safely instead of becoming stale UI")
    func mismatchedResultFailsSafely() async {
        let expected = Self.makeRound(question: "Expected?")
        let other = Self.makeRound(question: "Other?")
        let flow = SealFlowModel { _, choice in
            Self.stubResult(round: other, choice: choice)
        }

        flow.beginSeal(round: expected, choice: 0)
        await flow.waitForCurrentSeal()

        #expect(flow.stage == .failed)
        #expect(flow.failure == .unexpected)
        let mismatchedResultWasDiscarded = flow.result == nil
        #expect(mismatchedResultWasDiscarded)
    }

    private nonisolated static func makeRound(question: String) -> LocalRound {
        let createdAt = Date(timeIntervalSince1970: 1_788_600_000)
        return LocalRound(
            question: question,
            sides: ["Yes", "No"],
            crewName: "Saturday crew",
            createdAt: createdAt,
            sealDeadline: createdAt.addingTimeInterval(3_600)
        )
    }

    private nonisolated static func stubResult(round: LocalRound, choice: UInt8) -> LocalSealResult {
        let selectedIndex = choice == 1 ? 0 : 1
        return stubResult(
            round: round,
            selectedSideIndex: selectedIndex,
            selectedSide: round.sides[selectedIndex]
        )
    }

    private nonisolated static func stubResult(
        round: LocalRound,
        selectedSideIndex: Int,
        selectedSide: String
    ) -> LocalSealResult {
        return LocalSealResult(
            receipt: LocalSealReceipt(
                roundID: round.id,
                questionCommitment: round.questionCommitment,
                proofData: Data([0x01, 0x02]),
                proofBytes: 2,
                executeDuration: .milliseconds(1),
                keyLoadDuration: .milliseconds(2),
                proveDuration: .milliseconds(3),
                commitment: Data(repeating: 0xA5, count: 32)
            ),
            privateDisplay: LocalSealedDisplay(
                roundID: round.id,
                question: round.question,
                sides: round.sides,
                crewName: round.crewName,
                sealDeadline: round.sealDeadline,
                selectedSideIndex: selectedSideIndex,
                selectedSide: selectedSide,
                sealedAt: round.createdAt.addingTimeInterval(1)
            )
        )
    }
}

/// Models the native prover: cancellation of the awaiting presentation task does not
/// stop its work, and the first immutable result remains cached for the round.
private actor NativeLikeSealCache {
    typealias ResultFactory = @Sendable (LocalRound, UInt8) -> LocalSealResult

    private let makeResult: ResultFactory
    private var cachedResult: LocalSealResult?
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<Void, Never>?
    private var cacheWaiters: [CheckedContinuation<Void, Never>] = []

    init(makeResult: @escaping ResultFactory) {
        self.makeResult = makeResult
    }

    func seal(round: LocalRound, choice: UInt8) async -> LocalSealResult {
        if let cachedResult { return cachedResult }

        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { continuation in
            completion = continuation
        }

        let result = makeResult(round, choice)
        cachedResult = result
        cacheWaiters.forEach { $0.resume() }
        cacheWaiters.removeAll()
        return result
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func completeNativeWork() {
        completion?.resume()
        completion = nil
    }

    func waitUntilCached() async {
        guard cachedResult == nil else { return }
        await withCheckedContinuation { continuation in
            cacheWaiters.append(continuation)
        }
    }
}
