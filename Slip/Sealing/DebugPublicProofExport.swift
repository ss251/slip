#if DEBUG
import Foundation
import MidnightKit
import SwiftUI

/// Generates one real seal through the app-owned flow and writes only its public
/// local-proof bytes and commitment into Documents for Phase 6 format diagnostics.
/// This is not a transaction-bound ledger proof. The path is deliberately
/// launch-flag-only and does not exist in release builds.
struct DebugPublicProofExport: ViewModifier {
    let enabled: Bool
    let model: AppModel
    let flow: SealFlowModel

    @State private var started = false

    func body(content: Content) -> some View {
        content.task {
            guard enabled, !started else { return }
            started = true

            guard let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first else {
                model.inform("Public proof export failed.")
                return
            }
            let destination = documents.appendingPathComponent(
                "phase6-public-seal.json",
                isDirectory: false
            )

            // An interrupted or failed run must not leave a prior proof looking fresh.
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
            } catch {
                model.inform("Public proof export failed.")
                return
            }

            flow.beginSeal(round: model.localRound, choice: 1)
            await flow.waitForCurrentSeal()

            guard
                let receipt = flow.receipt,
                receipt.roundID == model.localRound.id,
                let commitment = receipt.commitment
            else {
                model.inform("Public proof export failed.")
                return
            }

            do {
                let artifact = try PublicProofArtifact(
                    proof: receipt.proofData,
                    commitment: commitment
                )
                try artifact.encoded().write(
                    to: destination,
                    options: [.atomic, .completeFileProtection]
                )
                model.inform("Public proof export ready.")
            } catch {
                model.inform("Public proof export failed.")
            }
        }
    }
}
#endif
