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
        // Proving fans out onto rayon workers; give them the caller's QoS so a
        // user-initiated seal never waits on default-priority threads.
        _ = slip_init_thread_pool()
    }

    public struct Proof: Sendable, Equatable {
        public let bytes: Int
        public let keyLoadDuration: Duration
        public let proveDuration: Duration
        /// The proof itself — what travels. Empty for the file-preimage path, which
        /// exists only for benchmarking against Node-built preimages.
        public let data: Data
    }

    /// Proves `circuit` from the `proofData` JSON the contract runtime produced.
    ///
    /// This is the product path: execution happened in `ContractRuntime` on this
    /// device, and the preimage — which carries the private transcript, i.e. data
    /// derived from the witness — is built in memory by the Rust side and never
    /// written anywhere. The returned `Proof.data` is the only thing that leaves.
    public func prove(circuit: String, proofData: String) async throws -> Proof {
        try await prove(circuit: circuit, proofData: proofData, bindingInput: nil)
    }

    /// Proves `circuit` from `proofData`, binding the proof to a transaction.
    ///
    /// A proof placed inside a transaction must commit to that transaction's binding
    /// input — `Transaction.prove` derives it from the call's address, entry point, gas
    /// and the transaction's binding commitment, and the proof server overwrites the
    /// preimage's `binding_input` with it before proving. A proof made without it is
    /// rejected on-chain as `Malformed(InvalidProof)`. Pass the value as big-endian hex
    /// (as midnight-js prints field elements); `nil` keeps the zero binding, which is
    /// only valid for local demonstration, never for submission.
    public func prove(circuit: String, proofData: String, bindingInput: String?) async throws -> Proof {
        try artifacts.validate(circuit: circuit)
        let irPath = artifacts.circuit(circuit).path
        let keyPath = artifacts.provingKey(circuit).path
        let paramsPath = artifacts.parametersDirectory.path

        return try await withCheckedThrowingContinuation { continuation in
            let thread = Thread {
                var keygenMs: UInt64 = 0, proveMs: UInt64 = 0, len = 0
                var ptr: UnsafeMutablePointer<UInt8>? = nil
                let rc = irPath.withCString { ir in paramsPath.withCString { params in
                    proofData.withCString { pd in circuit.withCString { key in keyPath.withCString { pk in
                        if let bindingInput {
                            return bindingInput.withCString { b in
                                slip_prove_proof_data_bound(ir, params, pd, key, pk, b, &keygenMs, &proveMs, &ptr, &len)
                            }
                        }
                        return slip_prove_proof_data(ir, params, pd, key, pk, &keygenMs, &proveMs, &ptr, &len)
                    } } } } }
                guard rc == 0, let ptr else {
                    continuation.resume(throwing: MidnightKitError.from(code: rc, circuit: circuit)); return
                }
                let data = Data(bytes: ptr, count: len)
                slip_free_bytes(ptr, len)
                continuation.resume(returning: Proof(
                    bytes: len,
                    keyLoadDuration: .milliseconds(Int(keygenMs)),
                    proveDuration: .milliseconds(Int(proveMs)),
                    data: data
                ))
            }
            thread.stackSize = 64 * 1024 * 1024
            // blst's own worker pool runs at default QoS; a higher caller QoS only creates a
            // priority inversion (Thread Performance Checker) without making proving faster.
            thread.qualityOfService = .default
            thread.start()
        }
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
                        proveDuration: .milliseconds(Int(proveMs)),
                        data: Data()
                    ))
                } else {
                    continuation.resume(throwing: MidnightKitError.from(code: rc, circuit: circuit))
                }
            }
            thread.stackSize = 64 * 1024 * 1024
            // blst's own worker pool runs at default QoS; a higher caller QoS only creates a
            // priority inversion (Thread Performance Checker) without making proving faster.
            thread.qualityOfService = .default
            thread.start()
        }
    }

    /// A proved, unbalanced transaction ready for a wallet to balance, sign and submit.
    public struct ProvedTransaction: Sendable, Equatable {
        /// Tagged ledger serialisation of the proved transaction — what leaves the device.
        public let data: Data
        public let duration: Duration
    }

    /// Assembles and proves a call transaction on this device.
    ///
    /// This is the network path. `proofData` comes from `ContractRuntime`; everything else
    /// is public chain context: the deployed contract's address, its current on-chain
    /// state (tagged `ContractState` bytes from the indexer) and block time. The native
    /// bridge builds the ledger-8 call prototype, partitions the transcript, derives the
    /// transaction binding input and proves with the bundled keys — the same steps the
    /// proof server and midnight-js perform, minus the proof server. The witness and the
    /// private transcript never leave process memory; the returned bytes are the proved,
    /// unbalanced transaction, which a wallet (holding the fee keys) balances and submits.
    public func buildProvedCallTransaction(
        circuit: String,
        proofData: String,
        networkID: String,
        contractAddressHex: String,
        contractState: Data,
        blockTime: UInt64,
        ttl: UInt64
    ) async throws -> ProvedTransaction {
        try artifacts.validate(circuit: circuit)
        let verifier = artifacts.keysDirectory.appendingPathComponent("\(circuit).verifier").path
        guard FileManager.default.fileExists(atPath: verifier) else { throw MidnightKitError.verifierKeyMissing(circuit: circuit) }
        let (zkir, keys, params) = (artifacts.circuitsDirectory.path, artifacts.keysDirectory.path, artifacts.parametersDirectory.path)
        return try await withCheckedThrowingContinuation { continuation in
            let thread = Thread {
                let started = ContinuousClock.now
                var ptr: UnsafeMutablePointer<UInt8>? = nil; var len = 0
                let rc = contractState.withUnsafeBytes { state -> Int32 in
                    proofData.withCString { pd in networkID.withCString { net in contractAddressHex.withCString { addr in
                    circuit.withCString { entry in verifier.withCString { vk in zkir.withCString { z in keys.withCString { k in params.withCString { p in
                        slip_build_proved_call_tx(pd, net, addr, entry, vk, state.bindMemory(to: UInt8.self).baseAddress, state.count,
                                                  blockTime, ttl, z, k, p, &ptr, &len)
                    } } } } } } } }
                }
                guard rc == 0, let ptr else {
                    continuation.resume(throwing: MidnightKitError.from(code: rc, circuit: circuit)); return
                }
                let data = Data(bytes: ptr, count: len)
                slip_free_bytes(ptr, len)
                continuation.resume(returning: ProvedTransaction(data: data, duration: ContinuousClock.now - started))
            }
            thread.stackSize = 64 * 1024 * 1024
            // blst's own worker pool runs at default QoS; a higher caller QoS only creates a
            // priority inversion (Thread Performance Checker) without making proving faster.
            thread.qualityOfService = .default
            thread.start()
        }
    }

    /// Confirms the linked archive is ours and not one of the earlier spike libraries.
    public nonisolated static func linkedLibraryIsMidnightKit() -> Bool {
        slip_prove_ping() == 44
    }
}
