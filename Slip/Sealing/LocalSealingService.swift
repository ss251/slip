import Foundation
import MidnightKit
import Security

/// Public material produced by a local seal.
///
/// `proofData` contains the zero-knowledge proof bytes returned by `Prover`. It is
/// deliberately not the runtime's `proofData` JSON, which contains private transcript
/// material and remains an implementation-local, in-memory value.
struct LocalSealReceipt: Sendable, Equatable {
    let proofData: Data
    let proofBytes: Int
    let executeDuration: Duration
    let keyLoadDuration: Duration
    let proveDuration: Duration
    let commitment: Data?
}

/// Errors safe to name in app UI. Associated strings and raw FFI codes from
/// `MidnightKitError` are intentionally discarded at this boundary.
enum AppSealError: Error, Equatable, Sendable {
    case invalidChoice
    case sealInProgress
    case secureRandomUnavailable
    case circuitNotFound
    case circuitUnreadable
    case provingKeyMissing
    case provingKeyUnreadable
    case parametersMissing
    case preimageInvalid
    case proveFailed
    case cancelled
    case runtime
    case proofDataInvalid
    case unexpected

    var displayName: String {
        switch self {
        case .invalidChoice: "Pick must be Yes or No"
        case .sealInProgress: "A seal is already in progress"
        case .secureRandomUnavailable: "Secure randomness unavailable"
        case .circuitNotFound: "Proof circuit unavailable"
        case .circuitUnreadable: "Proof circuit unreadable"
        case .provingKeyMissing: "Proving key missing"
        case .provingKeyUnreadable: "Proving key unreadable"
        case .parametersMissing: "Proof parameters missing"
        case .preimageInvalid, .proofDataInvalid: "Proof input invalid"
        case .proveFailed, .unexpected: "Couldn’t finish the proof"
        case .cancelled: "Proof cancelled"
        case .runtime: "Couldn’t prepare the proof"
        }
    }
}

extension AppSealError: LocalizedError {
    var errorDescription: String? { displayName }
}

/// Owns the app-only execute → prove flow for a local preview round.
///
/// The actor stores no JavaScriptCore objects. `ContractRuntime` is created, used, and
/// released within one synchronous call before the first suspension. The device secret,
/// choice, and runtime proof data stay in process memory; only the public proof and
/// commitment are returned.
actor LocalSealingService {
    private static let circuitName = "sealPick"
    private static let secretByteCount = 32

    private struct PrivateWitness: Sendable {
        let deviceSecret: Data
        let choice: UInt8
    }

    private enum State {
        case idle
        case sealing
        // Retain the witness only in actor memory so this local round can later grow a
        // reveal path without persisting private material.
        case sealed(receipt: LocalSealReceipt, witness: PrivateWitness)
    }

    private struct RuntimeOutput: Sendable {
        let proofData: String
        let executeDuration: Duration
        let commitment: Data?
    }

    private let prover: Prover
    private var state: State = .idle

    init(artifacts: ProofArtifacts) {
        prover = Prover(artifacts: artifacts)
    }

    /// The app resource layout. Contract artifacts are bundled by the app target under
    /// `ProofArtifacts/{zkir,keys,params}`; no host path or download fallback is allowed.
    nonisolated static func bundledArtifacts(in bundle: Bundle = .main) -> ProofArtifacts {
        let resources = bundle.resourceURL ?? bundle.bundleURL
        let root = resources.appendingPathComponent("ProofArtifacts", isDirectory: true)
        return ProofArtifacts(
            circuitsDirectory: root.appendingPathComponent("zkir", isDirectory: true),
            keysDirectory: root.appendingPathComponent("keys", isDirectory: true),
            parametersDirectory: root.appendingPathComponent("params", isDirectory: true)
        )
    }

    func seal(choice: UInt8) async throws -> LocalSealReceipt {
        guard choice == 0 || choice == 1 else { throw AppSealError.invalidChoice }

        switch state {
        case .idle:
            state = .sealing
        case .sealing:
            throw AppSealError.sealInProgress
        case .sealed(let receipt, _):
            return receipt
        }

        do {
            let witness = PrivateWitness(
                deviceSecret: try Self.secureRandomBytes(),
                choice: choice
            )
            let stewardSecret = try Self.secureRandomBytes()
            let runtime = try Self.executeSeal(witness: witness, stewardSecret: stewardSecret)

            // This is the first suspension. `executeSeal` has already released its
            // thread-confined ContractRuntime; only the in-memory JSON string crosses it.
            let proof = try await prover.prove(
                circuit: Self.circuitName,
                proofData: runtime.proofData
            )
            let receipt = LocalSealReceipt(
                proofData: proof.data,
                proofBytes: proof.bytes,
                executeDuration: runtime.executeDuration,
                keyLoadDuration: proof.keyLoadDuration,
                proveDuration: proof.proveDuration,
                commitment: runtime.commitment
            )
            state = .sealed(receipt: receipt, witness: witness)
            return receipt
        } catch {
            state = .idle
            throw Self.sanitized(error)
        }
    }

    /// Runs the complete local preview round without suspending, keeping JavaScriptCore
    /// creation and evaluation on one thread. The circuit itself derives the pick salt;
    /// the host supplies only `localSecretKey` and the range-checked `localPick` witness.
    private static func executeSeal(
        witness: PrivateWitness,
        stewardSecret: Data
    ) throws -> RuntimeOutput {
        let now = UInt64(Date().timeIntervalSince1970.rounded(.down))
        let driver = sealPickDriver(
            deviceSecretHex: hex(witness.deviceSecret),
            stewardSecretHex: hex(stewardSecret),
            choice: witness.choice,
            now: now
        )

        let started = ContinuousClock.now
        let proofData = try ContractRuntime().evaluate(driver)
        let executeDuration = ContinuousClock.now - started
        return RuntimeOutput(
            proofData: proofData,
            executeDuration: executeDuration,
            commitment: publicCommitment(from: proofData)
        )
    }

    private static func secureRandomBytes() throws -> Data {
        var bytes = Data(count: secretByteCount)
        let status: OSStatus = bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
        }
        guard status == errSecSuccess else { throw AppSealError.secureRandomUnavailable }
        return bytes
    }

    private static func hex(_ bytes: Data) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func sealPickDriver(
        deviceSecretHex: String,
        stewardSecretHex: String,
        choice: UInt8,
        now: UInt64
    ) -> String {
        let deadline = now + 3_600
        return """
        (function(){
          const rt = __compactRuntime, C = __slipContract;
          const ADDR = '11'.repeat(32), CPK = { bytes: new Uint8Array(32) };
          const fromHex = (h) => new Uint8Array(h.match(/../g).map(x => Number.parseInt(x, 16)));
          const STEWARD = fromHex('\(stewardSecretHex)');
          const MEMBER = fromHex('\(deviceSecretHex)');
          const NOW = \(now), DEADLINE = \(deadline);
          const w = (sk, p) => ({
            localSecretKey: ({ privateState }) => [privateState, sk],
            localPick:      ({ privateState }) => [privateState, p],
          });
          let state, priv;
          function call(sk, p, id, t, ...a) {
            const contract = new C.Contract(w(sk, p));
            const ctx = rt.createCircuitContext(ADDR, CPK, state, priv, undefined, undefined, t);
            ctx.currentQueryContext.block.secondsSinceEpoch = BigInt(t);
            const result = contract.impureCircuits[id](ctx, ...a);
            state = result.context.currentQueryContext.state;
            priv = result.context.currentPrivateState;
            return result;
          }
          const boot = new C.Contract(w(STEWARD, 0n));
          const initial = boot.initialState(rt.createConstructorContext(undefined, CPK));
          state = initial.currentContractState.data;
          priv = initial.currentPrivateState;
          call(STEWARD, 0n, 'enrollMember', NOW, C.pureCircuits.memberIdOf(MEMBER));
          call(STEWARD, 0n, 'createSlip', NOW + 10, new Uint8Array(32).fill(9), BigInt(DEADLINE));
          const pd = call(MEMBER, \(choice)n, 'sealPick', NOW + 600).proofData;
          const encode = (value) => JSON.parse(JSON.stringify(value, (_, item) =>
            typeof item === 'bigint' ? item.toString() :
              (item instanceof Uint8Array ? Array.from(item) : item)));
          return JSON.stringify({
            input: encode(pd.input),
            output: encode(pd.output),
            publicTranscript: encode(pd.publicTranscript),
            privateTranscriptOutputs: encode(pd.privateTranscriptOutputs),
          });
        })()
        """
    }

    /// `sealPick` publishes one 32-byte stored value: the commitment inserted into the
    /// seals map. Parsing only that public transcript operation avoids returning any
    /// private transcript material. A future compiler layout may make it unavailable;
    /// proof generation still succeeds and the receipt then carries `nil`.
    private static func publicCommitment(from proofData: String) -> Data? {
        guard
            let root = try? JSONSerialization.jsonObject(with: Data(proofData.utf8)) as? [String: Any],
            let transcript = root["publicTranscript"] as? [Any]
        else { return nil }

        // Ops without operands are bare strings ("lt", "member"); only object ops matter here.
        for operation in transcript.reversed().compactMap({ $0 as? [String: Any] }) {
            guard
                let push = operation["push"] as? [String: Any],
                push["storage"] as? Bool == true,
                let value = push["value"] as? [String: Any],
                value["tag"] as? String == "cell",
                let content = value["content"] as? [String: Any],
                let nested = content["value"] as? [Any],
                let rawBytes = nested.first as? [NSNumber],
                rawBytes.count == secretByteCount,
                rawBytes.allSatisfy({ (0...255).contains($0.intValue) })
            else { continue }

            return Data(rawBytes.map { UInt8($0.intValue) })
        }
        return nil
    }

    private static func sanitized(_ error: Error) -> AppSealError {
        if let appError = error as? AppSealError { return appError }
        if error is CancellationError { return .cancelled }
        guard let error = error as? MidnightKitError else { return .unexpected }

        return switch error {
        case .circuitNotFound: .circuitNotFound
        case .circuitUnreadable: .circuitUnreadable
        case .provingKeyMissing: .provingKeyMissing
        case .provingKeyUnreadable: .provingKeyUnreadable
        case .parametersMissing: .parametersMissing
        case .preimageInvalid: .preimageInvalid
        case .proveFailed: .proveFailed
        case .cancelled: .cancelled
        case .runtime: .runtime
        case .proofDataInvalid: .proofDataInvalid
        }
    }
}
