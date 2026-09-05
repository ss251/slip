import Foundation
import MidnightKit
import Observation

/// Public facts about network seals, for the ticket: tx id and commitment per round.
@Observable @MainActor
final class NetworkSealTracker {
    private(set) var receipts: [UUID: NetworkSealReceipt] = [:]
    private(set) var confirmations: [UUID: ConfirmationStatus] = [:]
    let relayHost: String?
    /// `memberIdOf(secret)`: the public identity the steward enrols. Public by construction.
    var memberIDHex: String?

    init(relayHost: String? = nil) { self.relayHost = relayHost }
    func record(_ receipt: NetworkSealReceipt, for roundID: UUID) { receipts[roundID] = receipt }
    func record(_ status: ConfirmationStatus, for roundID: UUID) { confirmations[roundID] = status }
    func receipt(for roundID: UUID) -> NetworkSealReceipt? { receipts[roundID] }
}

/// Runs the network seal and presents it through the same `LocalSealResult` the screens
/// already render, so the sealed ticket is one screen whether the proof stayed local or
/// went to the network.
enum NetworkSealAdapter {
    static func operation(service: NetworkSealingService, tracker: NetworkSealTracker) -> SealFlowModel.SealOperation {
        { round, choice in
            guard let side = round.sideLabel(for: choice) else { throw AppSealError.invalidChoice }
            let sealedAt = Date()
            let network = try await service.seal(choice: choice)
            await tracker.record(network, for: round.id)
            let receipt = LocalSealReceipt(
                roundID: round.id,
                questionCommitment: Data(),               // lives on chain; not derived client-side
                proofData: Data(),                        // the proof never needs to be shown; size is reported below
                proofBytes: network.transactionBytes,
                executeDuration: network.executeDuration,
                keyLoadDuration: .zero,
                proveDuration: network.assembleDuration,
                commitment: network.commitment)
            let display = LocalSealedDisplay(
                roundID: round.id, question: round.question, sides: round.sides, crewName: round.crewName,
                sealDeadline: round.sealDeadline, selectedSideIndex: choice == 1 ? 0 : 1, selectedSide: side, sealedAt: sealedAt)
            Task { [tracker] in
                if let status = try? await service.confirmation(of: network) { await tracker.record(status, for: round.id) }
            }
            return LocalSealResult(receipt: receipt, privateDisplay: display)
        }
    }

    /// The flow for this launch: network when a setup exists, otherwise the local round.
    @MainActor
    static func makeFlow(setup: NetworkSetup?, tracker: NetworkSealTracker, secretStore: any SecretStore = KeychainSecretStore()) -> SealFlowModel {
        guard let setup, let secret = try? DeviceIdentity.secret(store: secretStore) else { return SealFlowModel() }
        let service = NetworkSealingService(
            relay: HTTPStewardRelay(baseURL: setup.relayURL),
            prover: Prover(artifacts: LocalSealingService.bundledArtifacts()),
            contractAddressHex: setup.contractAddressHex,
            deviceSecret: secret)
        Task { @MainActor in tracker.memberIDHex = try? await service.memberIDHex() }
        return SealFlowModel(sealOperation: operation(service: service, tracker: tracker))
    }
}
