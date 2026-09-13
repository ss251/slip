import Observation
import SwiftUI

/// App-owned presentation state for one local execute → prove operation.
///
/// The task is tied to a `LocalRound` identity. Leaving that round invalidates its
/// presentation completion, so a late native proof cannot move a different screen or
/// relabel its private display facts.
@MainActor @Observable
final class SealFlowModel {
    typealias SealOperation = @Sendable (LocalRound, UInt8) async throws -> LocalSealResult
    typealias RoundOperation = @Sendable (UUID, LocalRoundAction) async throws -> LocalRoundResult
    typealias RoundReadOperation = @Sendable (UUID) async -> LocalRoundResult?

    enum LocalRoundAction: Sendable { case reveal, settle(UInt8), dispute }

    enum Stage: Equatable { case choosing, proving, sealed, failed }

    private(set) var stage: Stage = .choosing
    private(set) var result: LocalSealResult?
    private(set) var failure: AppSealError?
    private(set) var activeRoundID: UUID?
    private(set) var roundResult: LocalRoundResult?
    private(set) var roundFailure: AppSealError?
    private(set) var isRoundBusy = false

    var receipt: LocalSealReceipt? { result?.receipt }
    var sealedDisplay: LocalSealedDisplay? { result?.privateDisplay }

    @ObservationIgnored private let sealOperation: SealOperation
    @ObservationIgnored private let roundOperation: RoundOperation
    @ObservationIgnored private let readRound: RoundReadOperation
    @ObservationIgnored private var sealTask: Task<Void, Never>?
    @ObservationIgnored private var roundTask: Task<Void, Never>?
    @ObservationIgnored private var roundToken: UUID?
    @ObservationIgnored private var operationToken: UUID?
    @ObservationIgnored private var feedbackRoundIDs: Set<UUID> = []

    init() {
        let service = LocalSealingService(
            artifacts: LocalSealingService.bundledArtifacts()
        )
        sealOperation = { round, choice in
            try await service.seal(round: round, choice: choice)
        }
        readRound = { await service.currentResult(roundID: $0) }
        roundOperation = { id, action in
            switch action {
            case .reveal: try await service.reveal(roundID: id)
            case .settle(let outcome): try await service.settle(roundID: id, outcome: outcome)
            case .dispute: try await service.dispute(roundID: id)
            }
        }
    }

    convenience init(sealOperation: @escaping SealOperation) {
        self.init(sealOperation: sealOperation, roundOperation: { _, _ in throw AppSealError.unexpected })
    }

    init(
        sealOperation: @escaping SealOperation,
        roundOperation: @escaping RoundOperation,
        readRound: @escaping RoundReadOperation = { _ in nil }
    ) {
        self.sealOperation = sealOperation
        self.roundOperation = roundOperation
        self.readRound = readRound
    }

    /// Captures the immutable round and choice synchronously, then owns the task that
    /// performs the proof. Views observe `stage`; this model never navigates itself.
    func beginSeal(round: LocalRound, choice: UInt8) {
        guard stage != .proving, !isRoundBusy else { return }

        if let existing = result, existing.receipt.roundID == round.id {
            guard metadataMatches(existing, round: round) else {
                operationToken = nil
                activeRoundID = round.id
                result = nil
                roundResult = nil
                roundFailure = nil
                failure = .roundIdentityConflict
                stage = .failed
                return
            }
            activeRoundID = round.id
            failure = nil
            stage = .sealed
            return
        }

        sealTask?.cancel()
        let token = UUID()
        operationToken = token
        activeRoundID = round.id
        result = nil
        roundResult = nil
        roundFailure = nil
        failure = nil
        stage = .proving

        let operation = sealOperation
        let read = readRound
        sealTask = Task { @MainActor [weak self] in
            do {
                let sealed = try await operation(round, choice)
                let localResult = await read(round.id)
                guard !Task.isCancelled else { return }
                self?.finish(sealed, expectedRound: round, token: token)
                if self?.operationToken == token, self?.stage == .sealed,
                   localResult?.round == round {
                    self?.roundResult = localResult
                }
            } catch {
                guard !Task.isCancelled else { return }
                let safeError = (error as? AppSealError) ?? .unexpected
                self?.finish(safeError, roundID: round.id, token: token)
            }
        }
    }

    /// Invalidates only the operation presented by the departing round. Cancelling the
    /// Swift task cannot promise cancellation inside native proving, so the token check
    /// is the authority that prevents a late result from changing UI state.
    func depart(roundID: UUID) {
        guard activeRoundID == roundID else { return }
        operationToken = nil
        sealTask?.cancel()
        sealTask = nil
        roundToken = nil
        roundTask?.cancel()
        roundTask = nil
        isRoundBusy = false
        activeRoundID = nil

        if stage == .proving {
            failure = nil
            stage = .choosing
        }
    }

    /// A replacement invite can reuse a UUID. Drop all presentation for its previous
    /// incarnation and invalidate completion tokens before showing the replacement.
    func discard() {
        if let activeRoundID { depart(roundID: activeRoundID) }
        // A departed round's cached result may differ from AppModel's current UUID.
        // Replacing the invite clears that cached presentation too.
        operationToken = nil
        roundToken = nil
        sealTask?.cancel()
        roundTask?.cancel()
        sealTask = nil
        roundTask = nil
        activeRoundID = nil
        isRoundBusy = false
        result = nil
        roundResult = nil
        roundFailure = nil
        failure = nil
        stage = .choosing
        feedbackRoundIDs.removeAll()
    }

    func chooseAgain() {
        guard stage == .failed else { return }
        failure = nil
        stage = .choosing
    }

    /// Returns true exactly once for a successfully sealed round, so revisiting a
    /// ticket cannot replay the heavy success haptic.
    func consumeSealFeedback(roundID: UUID) -> Bool {
        guard result?.receipt.roundID == roundID, stage == .sealed else { return false }
        return feedbackRoundIDs.insert(roundID).inserted
    }

    /// Test synchronization without exposing the task to app views.
    func waitForCurrentSeal() async {
        let currentTask = sealTask
        await currentTask?.value
    }

    func beginReveal(roundID: UUID) { beginRoundAction(.reveal, roundID: roundID) }
    func beginSettle(roundID: UUID, outcome: UInt8) { beginRoundAction(.settle(outcome), roundID: roundID) }
    func beginDispute(roundID: UUID) { beginRoundAction(.dispute, roundID: roundID) }

    func waitForCurrentRoundAction() async { await roundTask?.value }

    private func beginRoundAction(_ action: LocalRoundAction, roundID: UUID) {
        guard !isRoundBusy, stage != .proving else { return }
        guard let sealed = result, sealed.receipt.roundID == roundID else {
            roundFailure = .unexpected
            return
        }
        let token = UUID()
        roundToken = token
        activeRoundID = roundID
        roundFailure = nil
        isRoundBusy = true
        let operation = roundOperation
        let expectedStage: LocalRoundStage = switch action {
        case .reveal: .revealed
        case .settle: .settled
        case .dispute: .disputed
        }
        roundTask = Task { @MainActor [weak self] in
            do {
                let updated = try await operation(roundID, action)
                guard let self, !Task.isCancelled,
                      self.roundToken == token, self.activeRoundID == roundID else { return }
                guard updated.stage == expectedStage,
                      updated.roundID == roundID, updated.round.id == roundID,
                      updated.round.questionCommitment == sealed.receipt.questionCommitment else {
                    self.roundFailure = .unexpected
                    self.isRoundBusy = false
                    self.roundTask = nil
                    return
                }
                self.roundResult = updated
                self.isRoundBusy = false
                self.roundTask = nil
            } catch {
                guard let self, !Task.isCancelled,
                      self.roundToken == token, self.activeRoundID == roundID else { return }
                self.roundFailure = (error as? AppSealError) ?? .unexpected
                self.isRoundBusy = false
                self.roundTask = nil
            }
        }
    }

    private func finish(
        _ sealed: LocalSealResult,
        expectedRound round: LocalRound,
        token: UUID
    ) {
        guard
            operationToken == token,
            activeRoundID == round.id
        else { return }

        let selectedSideIndex = sealed.privateDisplay.selectedSideIndex
        guard
            metadataMatches(sealed, round: round),
            round.sides.count == 2,
            round.sides.indices.contains(selectedSideIndex),
            sealed.privateDisplay.selectedSide == round.sides[selectedSideIndex]
        else {
            failure = .unexpected
            stage = .failed
            sealTask = nil
            return
        }

        result = sealed
        failure = nil
        stage = .sealed
        sealTask = nil
    }

    private func metadataMatches(_ sealed: LocalSealResult, round: LocalRound) -> Bool {
        sealed.privateDisplay.roundID == round.id
            && sealed.receipt.roundID == round.id
            && sealed.receipt.questionCommitment == round.questionCommitment
            && sealed.privateDisplay.question == round.question
            && sealed.privateDisplay.sides == round.sides
            && sealed.privateDisplay.crewName == round.crewName
            && sealed.privateDisplay.sealDeadline == round.sealDeadline
    }

    private func finish(_ error: AppSealError, roundID: UUID, token: UUID) {
        guard operationToken == token, activeRoundID == roundID else { return }
        failure = error
        stage = .failed
        sealTask = nil
    }
}

/// A safety timer, kept separate from ornamental animation and testable without a view.
struct SealHold: Equatable {
    private(set) var began: TimeInterval?
    mutating func start(at time: TimeInterval) { began = time }
    mutating func cancel() { began = nil }
    func progress(at time: TimeInterval) -> Double {
        guard let began else { return 0 }
        return min(1, max(0, (time - began) / SlipMotion.holdDuration))
    }
    mutating func finish(at time: TimeInterval) -> Bool {
        let complete = progress(at: time) >= 1
        cancel()
        return complete
    }
}
