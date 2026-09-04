import Foundation
import CSlipProve

/// Generates zero-knowledge proofs on this device.
///
/// The product claim rests entirely on this type: a sealed pick is proved here, on the
/// user's phone, and only the proof and the commitment ever travel. There is no remote
/// proving mode and there must never be one — a proof server necessarily receives the
/// witness in the clear, which would make the privacy promise policy rather than
/// architecture. If proving fails, it fails; it does not fall back.
///
/// Measured on an iPhone 15 Pro (A17 Pro), Slip's real `sealPick` circuit (k=14):
/// proving-key load 24 ms, prove 1776 ms, proof 4480 bytes, peak RSS 290 MB.
public actor Prover {
    private let artifacts: ProofArtifacts

    public init(artifacts: ProofArtifacts = .bundled()) {
        self.artifacts = artifacts
    }

    public struct Proof: Sendable, Equatable {
        public let bytes: Int
        public let keyLoadDuration: Duration
        public let proveDuration: Duration
    }

    /// Proves `circuit` against a preimage produced by executing the contract.
    ///
    /// Runs off the calling thread on a dedicated 64 MB stack. PLONK proving is
    /// stack-hungry and the default stack for a non-main thread is far smaller than
    /// the main thread's; this is a precaution rather than an observed crash, but the
    /// cost of being wrong is a hard crash in the one flow the product is named after.
    ///
    /// Peak memory is ~290 MB transient. That is comfortable in a foreground app
    /// (Jetsam allows ~2 GB even on 4 GB devices) but it rules out app extensions,
    /// which cap near 120 MB. "Seal from the share sheet" is not reachable without a
    /// materially smaller circuit.
    public func prove(circuit: String, preimage: URL) async throws -> Proof {
        try artifacts.validate(circuit: circuit)

        let irPath = artifacts.circuit(circuit).path
        let keyPath = artifacts.provingKey(circuit).path
        let paramsPath = artifacts.parametersDirectory.path
        let preimagePath = preimage.path

        return try await withCheckedThrowingContinuation { continuation in
            let thread = Thread {
                var keygenMs: UInt64 = 0, proveMs: UInt64 = 0, proofBytes: UInt64 = 0
                let rc = irPath.withCString { ir in
                    paramsPath.withCString { params in
                        preimagePath.withCString { pre in
                            keyPath.withCString { key in
                                slip_prove_circuit(ir, params, pre, key, &keygenMs, &proveMs, &proofBytes)
                            }
                        }
                    }
                }
                if rc == 0 {
                    continuation.resume(returning: Proof(
                        bytes: Int(proofBytes),
                        keyLoadDuration: .milliseconds(Int(keygenMs)),
                        proveDuration: .milliseconds(Int(proveMs))
                    ))
                } else {
                    continuation.resume(throwing: MidnightKitError.from(code: rc, circuit: circuit))
                }
            }
            thread.stackSize = 64 * 1024 * 1024
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    /// Confirms the linked archive is ours and not one of the earlier spike libraries.
    public nonisolated static func linkedLibraryIsMidnightKit() -> Bool {
        slip_prove_ping() == 44
    }
}
