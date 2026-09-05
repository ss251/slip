#if DEBUG
import Foundation
import SwiftUI

/// Explicit screenshot fixtures for the non-preview result views. These values are
/// synthetic public examples, never circuit inputs supplied through launch flags.
/// The entire fixture implementation is absent from release builds.
enum LocalRoundPreviewFixture: String, CaseIterable, Sendable {
    case sealed
    case revealed
    case settledWon = "settled-won"
    case settledLost = "settled-lost"
    case disputed
    case mismatch
    case parametersMissing

    private static let syntheticChoice: UInt8 = 1
    private static let sampleDate = Date(timeIntervalSince1970: 1_788_000_000)

    var defaultScreen: SlipScreen {
        switch self {
        case .sealed: .room
        case .revealed, .parametersMissing: .opening
        case .settledWon, .settledLost: .verdict
        case .disputed: .voided
        case .mismatch: .mismatch
        }
    }

    private var stage: LocalRoundStage {
        switch self {
        case .sealed, .mismatch, .parametersMissing: .sealed
        case .revealed: .revealed
        case .settledWon, .settledLost: .settled
        case .disputed: .disputed
        }
    }

    private var injectedFailure: AppSealError? {
        switch self {
        case .mismatch: .revealMismatch
        case .parametersMissing: .parametersMissing
        default: nil
        }
    }

    @MainActor func configure(_ model: AppModel) {
        model.isPreview = false
        model.startLocalRound(
            question: PreviewContent.question,
            sides: ["Yes", "No"],
            crewName: "Synthetic QA fixture",
            createdAt: Self.sampleDate
        )
    }

    @MainActor func makeFlow(round: LocalRound) -> SealFlowModel {
        let seal = Self.syntheticSeal(round: round)
        let publicResult = result(round: round)
        let safeFailure = injectedFailure ?? .cancelled
        return SealFlowModel(
            sealOperation: { requestedRound, requestedChoice in
                guard requestedRound == round, requestedChoice == Self.syntheticChoice else {
                    throw AppSealError.invalidRoundMetadata
                }
                return seal
            },
            // Screenshot fixtures never execute, prove or submit an operation.
            // A tap beyond the seeded state reports a safe named error instead.
            roundOperation: { _, _ in throw safeFailure },
            readRound: { id in id == round.id ? publicResult : nil }
        )
    }

    @MainActor func bootstrap(model: AppModel, flow: SealFlowModel) async {
        let round = model.localRound
        flow.beginSeal(round: round, choice: Self.syntheticChoice)
        await flow.waitForCurrentSeal()
        guard !Task.isCancelled, flow.receipt?.roundID == round.id else { return }
        model.markLocalSeal(roundID: round.id)
        if injectedFailure != nil {
            flow.beginReveal(roundID: round.id)
            await flow.waitForCurrentRoundAction()
        }
    }

    private func result(round: LocalRound) -> LocalRoundResult {
        let opened = stage != .sealed
        let outcome: UInt8? = switch self {
        case .settledWon: 1
        case .settledLost: 0
        case .disputed: 3
        default: nil
        }
        var steps: [LocalProofStep] = [.enrollMember, .createSlip, .sealPick]
        if opened { steps.append(.reveal) }
        if stage == .settled || stage == .disputed { steps.append(.settle) }
        if stage == .disputed { steps.append(.dispute) }
        return LocalRoundResult(
            roundID: round.id,
            round: round,
            stage: stage,
            revealedChoice: opened ? Self.syntheticChoice : nil,
            outcome: outcome,
            tallyYes: opened ? 1 : 0,
            tallyNo: 0,
            disputedBy: stage == .disputed ? Data("synthetic-public-player".utf8) : nil,
            steps: steps.map {
                LocalStepReceipt(step: $0, executeDuration: .zero, keyLoadDuration: .zero,
                                 proveDuration: .zero, proofBytes: 0)
            }
        )
    }

    private static func syntheticSeal(round: LocalRound) -> LocalSealResult {
        LocalSealResult(
            receipt: LocalSealReceipt(
                roundID: round.id,
                questionCommitment: round.questionCommitment,
                proofData: Data(),
                proofBytes: 0,
                executeDuration: .zero,
                keyLoadDuration: .zero,
                proveDuration: .zero,
                commitment: nil
            ),
            privateDisplay: LocalSealedDisplay(
                roundID: round.id,
                question: round.question,
                sides: round.sides,
                crewName: round.crewName,
                sealDeadline: round.sealDeadline,
                selectedSideIndex: 0,
                selectedSide: "Yes",
                sealedAt: sampleDate
            )
        )
    }
}

/// Shows a persistent screenshot disclaimer only for the explicit debug fixture
/// launch flag. Canonical `--preview` captures have no extra banner or seeding.
struct DebugLocalFixtureLaunch: ViewModifier {
    let fixture: LocalRoundPreviewFixture?
    let model: AppModel
    let flow: SealFlowModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var didBootstrap = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: SlipSpacing.zero) {
                if fixture != nil {
                    Text("Synthetic QA fixture · no proofs run")
                        .font(SlipFont.captionBold)
                        .foregroundStyle(SlipColor.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, SlipSpacing.screen)
                        .padding(.vertical, SlipSpacing.small)
                        .frame(maxWidth: .infinity)
                        .background(SlipColor.fill)
                }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active, !didBootstrap, let fixture else { return }
                await fixture.bootstrap(model: model, flow: flow)
                if !Task.isCancelled { didBootstrap = true }
            }
    }
}
#endif
