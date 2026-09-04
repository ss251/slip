import SwiftUI
import MidnightKit

/// The UI owns only the local pick and safe display state. No network or persistence.
@MainActor @Observable
final class SealFlowModel {
    enum Stage: Equatable { case choosing, proving, sealed, failed }
    private(set) var stage: Stage = .choosing
    private(set) var receipt: LocalSealReceipt?
    private(set) var failure: AppSealError?
    private var service: LocalSealingService

    init() {
        let root = Bundle.main.resourceURL!.appendingPathComponent("ProofArtifacts")
        service = LocalSealingService(artifacts: ProofArtifacts(
            circuitsDirectory: root.appendingPathComponent("zkir"),
            keysDirectory: root.appendingPathComponent("keys"),
            parametersDirectory: root.appendingPathComponent("params")))
    }

    func seal(choice: UInt8) async {
        guard stage != .proving, stage != .sealed else { return }
        stage = .proving
        failure = nil
        do {
            receipt = try await service.seal(choice: choice)
            stage = .sealed
        } catch {
            failure = (error as? AppSealError) ?? .unexpected
            stage = .failed
        }
    }

    func chooseAgain() { guard stage == .failed else { return }; stage = .choosing; failure = nil }
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
