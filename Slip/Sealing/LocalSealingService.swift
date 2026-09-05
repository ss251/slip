import CryptoKit
import Foundation
import MidnightKit
import Security

/// Immutable public metadata for one app-only local demonstration round.
///
/// Side order follows the contract encoding: index 0 is choice `1`, index 1 is
/// choice `0`. The UUID prevents a receipt for one local round being reused or
/// relabelled as another, even when their human-readable metadata is identical.
struct LocalRound: Identifiable, Sendable, Equatable {
    let id: UUID
    let question: String
    let sides: [String]
    let crewName: String
    let createdAt: Date
    let sealDeadline: Date

    init(
        id: UUID = UUID(),
        question: String,
        sides: [String],
        crewName: String,
        createdAt: Date = Date(),
        sealDeadline: Date? = nil
    ) {
        self.id = id
        self.question = question
        self.sides = sides
        self.crewName = crewName
        self.createdAt = createdAt
        self.sealDeadline = sealDeadline ?? createdAt.addingTimeInterval(3_600)
    }

    /// SHA-256 over a domain-separated, length-prefixed canonical encoding of the
    /// public metadata this local proof demonstrates. Text is normalized to NFC,
    /// side order is preserved, and dates use whole Unix seconds like Compact.
    var questionCommitment: Data {
        var canonical = Data("slip:local-round:v1".utf8)
        Self.append(id.uuidString.lowercased(), to: &canonical)
        Self.append(question.precomposedStringWithCanonicalMapping, to: &canonical)
        Self.append(UInt64(sides.count), to: &canonical)
        for side in sides {
            Self.append(side.precomposedStringWithCanonicalMapping, to: &canonical)
        }
        Self.append(crewName.precomposedStringWithCanonicalMapping, to: &canonical)
        Self.append(createdAt.compactTimestamp, to: &canonical)
        Self.append(sealDeadline.compactTimestamp, to: &canonical)
        return Data(SHA256.hash(data: canonical))
    }

    func sideLabel(for choice: UInt8) -> String? {
        guard sides.count == 2 else { return nil }
        return choice == 1 ? sides[0] : choice == 0 ? sides[1] : nil
    }

    private static func append(_ string: String, to data: inout Data) {
        let bytes = Data(string.utf8)
        append(UInt64(bytes.count), to: &data)
        data.append(bytes)
    }

    private static func append(_ integer: UInt64, to data: inout Data) {
        var bigEndian = integer.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
}

private extension Date {
    var compactTimestamp: UInt64 {
        let seconds = timeIntervalSince1970.rounded(.down)
        // `Double(UInt64.max)` rounds up to 2^64. A strict bound avoids a trap
        // when converting that rounded, non-representable endpoint to UInt64.
        guard seconds.isFinite, seconds > 0, seconds < Double(UInt64.max) else { return 0 }
        return UInt64(seconds)
    }
}

/// Public material produced by a local seal demonstration.
///
/// `proofData` contains the zero-knowledge proof bytes returned by `Prover`. It is
/// deliberately not the runtime's `proofData` JSON, which contains private transcript
/// material and remains an implementation-local, in-memory value.
struct LocalSealReceipt: Sendable, Equatable {
    let roundID: UUID
    let questionCommitment: Data
    let proofData: Data
    let proofBytes: Int
    let executeDuration: Duration
    let keyLoadDuration: Duration
    let proveDuration: Duration
    let commitment: Data?
}

/// The private display facts captured when sealing begins. Never log, serialize, or
/// persist this value: `selectedSide` reveals the witness. Views use this immutable
/// snapshot instead of mutable draft fields after the proof completes.
struct LocalSealedDisplay: Sendable, Equatable {
    let roundID: UUID
    let question: String
    let sides: [String]
    let crewName: String
    let sealDeadline: Date
    let selectedSideIndex: Int
    let selectedSide: String
    let sealedAt: Date
}

/// Keeps private display facts beside—but distinct from—the public receipt. This entire
/// record is session-only because it contains `privateDisplay`.
struct LocalSealResult: Sendable, Equatable {
    let receipt: LocalSealReceipt
    let privateDisplay: LocalSealedDisplay
}

/// Errors safe to name in app UI. Associated strings and raw FFI codes from
/// `MidnightKitError` are intentionally discarded at this boundary.
enum AppSealError: Error, Equatable, Sendable {
    case invalidChoice
    case invalidRoundMetadata
    case roundIdentityConflict
    case sealDeadlinePassed
    case sealDeadlineTooSoon
    case sealDeadlineTooFar
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
        case .invalidChoice: "Pick must be one of the two sides"
        case .invalidRoundMetadata: "This local slip is incomplete"
        case .roundIdentityConflict: "This local slip changed"
        case .sealDeadlinePassed: "Sealing has closed"
        case .sealDeadlineTooSoon: "Deadline must be more than 5 minutes away"
        case .sealDeadlineTooFar: "Deadline must be within 365 days"
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

/// Owns app-only execute → prove flows for local demonstration rounds.
///
/// The actor stores no JavaScriptCore objects. `ContractRuntime` is created, used, and
/// released within one synchronous call before the first suspension. Device secrets,
/// choices, and runtime proof data stay in process memory; only public proof material is
/// exposed separately from the private display snapshot. There is no submit path.
actor LocalSealingService {
    private static let circuitName = "sealPick"
    private static let parameterFileName = "bls_midnight_2p14"
    private static let secretByteCount = 32
    private static let minimumSealWindow: UInt64 = 300
    private static let maximumSealWindow: UInt64 = 31_536_000

    private struct PrivateWitness: Sendable {
        let deviceSecret: Data
        let choice: UInt8
    }

    private struct SealedRound: Sendable {
        let round: LocalRound
        let result: LocalSealResult
        // Retained only in actor memory so a future session-scoped reveal can use the
        // same witness. No persistence is implied or provided.
        let witness: PrivateWitness
    }

    private struct RuntimeOutput: Sendable {
        let proofData: String
        let executeDuration: Duration
        let commitment: Data?
    }

    private let artifacts: ProofArtifacts
    private let prover: Prover
    private var activeRound: LocalRound?
    private var sealedRounds: [UUID: SealedRound] = [:]

    init(artifacts: ProofArtifacts) {
        self.artifacts = artifacts
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

    /// Mirrors `createSlip`'s exact public deadline bounds without entering the
    /// runtime. Creation UI can use the same helper to reject an impossible round.
    nonisolated static func deadlineError(
        for deadline: Date,
        relativeTo now: Date = Date()
    ) -> AppSealError? {
        let nowSeconds = now.compactTimestamp
        let deadlineSeconds = deadline.compactTimestamp

        guard deadlineSeconds > nowSeconds else { return .sealDeadlinePassed }

        // Compact requires blockTime < deadline - 300, so exactly five minutes
        // is intentionally still too soon.
        guard
            deadlineSeconds >= minimumSealWindow,
            nowSeconds < deadlineSeconds - minimumSealWindow
        else { return .sealDeadlineTooSoon }

        // Compact requires blockTime >= deadline - 31_536_000. Subtraction keeps
        // this overflow-free at the full UInt64 boundary.
        if
            deadlineSeconds >= maximumSealWindow,
            nowSeconds < deadlineSeconds - maximumSealWindow
        {
            return .sealDeadlineTooFar
        }
        return nil
    }

    func seal(round: LocalRound, choice: UInt8) async throws -> LocalSealResult {
        guard choice == 0 || choice == 1 else { throw AppSealError.invalidChoice }
        guard
            !round.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            round.sides.count == 2,
            round.sides.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
            !round.crewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw AppSealError.invalidRoundMetadata }

        if let sealed = sealedRounds[round.id] {
            guard sealed.round == round else { throw AppSealError.roundIdentityConflict }
            return sealed.result
        }
        if let activeRound {
            guard activeRound == round else {
                if activeRound.id == round.id { throw AppSealError.roundIdentityConflict }
                throw AppSealError.sealInProgress
            }
            throw AppSealError.sealInProgress
        }

        let sealedAt = Date()
        if let deadlineError = Self.deadlineError(
            for: round.sealDeadline,
            relativeTo: sealedAt
        ) { throw deadlineError }
        guard let selectedSide = round.sideLabel(for: choice) else {
            throw AppSealError.invalidChoice
        }
        try preflightArtifacts()

        let privateDisplay = LocalSealedDisplay(
            roundID: round.id,
            question: round.question,
            sides: round.sides,
            crewName: round.crewName,
            sealDeadline: round.sealDeadline,
            selectedSideIndex: choice == 1 ? 0 : 1,
            selectedSide: selectedSide,
            sealedAt: sealedAt
        )
        activeRound = round

        do {
            let witness = PrivateWitness(
                deviceSecret: try Self.secureRandomBytes(),
                choice: choice
            )
            let stewardSecret = try Self.secureRandomBytes()
            let execution = try Self.executeSeal(
                round: round,
                witness: witness,
                stewardSecret: stewardSecret,
                sealedAt: sealedAt
            )

            // This is the first suspension. `executeSeal` has already released its
            // thread-confined ContractRuntime; only the in-memory JSON string crosses it.
            let proof = try await prover.prove(
                circuit: Self.circuitName,
                proofData: execution.proofData
            )
            let receipt = LocalSealReceipt(
                roundID: round.id,
                questionCommitment: round.questionCommitment,
                proofData: proof.data,
                proofBytes: proof.bytes,
                executeDuration: execution.executeDuration,
                keyLoadDuration: proof.keyLoadDuration,
                proveDuration: proof.proveDuration,
                commitment: execution.commitment
            )
            let result = LocalSealResult(receipt: receipt, privateDisplay: privateDisplay)
            sealedRounds[round.id] = SealedRound(round: round, result: result, witness: witness)
            activeRound = nil
            return result
        } catch {
            activeRound = nil
            throw Self.sanitized(error)
        }
    }

    /// Checks the exact app-bundle layout before private data enters the runtime. This
    /// app-layer preflight names a missing k=14 parameter file even though the protected
    /// MidnightKit error mapper cannot currently distinguish that FFI failure.
    private func preflightArtifacts() throws {
        let fileManager = FileManager.default
        let circuit = artifacts.circuitsDirectory.appendingPathComponent("\(Self.circuitName).zkir")
        let key = artifacts.keysDirectory.appendingPathComponent("\(Self.circuitName).prover")
        let parameters = artifacts.parametersDirectory.appendingPathComponent(Self.parameterFileName)

        guard fileManager.fileExists(atPath: circuit.path) else {
            throw AppSealError.circuitNotFound
        }
        guard fileManager.isReadableFile(atPath: circuit.path) else {
            throw AppSealError.circuitUnreadable
        }
        guard fileManager.fileExists(atPath: key.path) else {
            throw AppSealError.provingKeyMissing
        }
        guard fileManager.isReadableFile(atPath: key.path) else {
            throw AppSealError.provingKeyUnreadable
        }
        guard
            fileManager.fileExists(atPath: parameters.path),
            fileManager.isReadableFile(atPath: parameters.path)
        else { throw AppSealError.parametersMissing }
    }

    /// Runs the complete local demonstration round without suspending, keeping
    /// JavaScriptCore creation and evaluation on one thread. The circuit derives the
    /// pick salt; the host supplies only `localSecretKey` and range-checked `localPick`.
    private static func executeSeal(
        round: LocalRound,
        witness: PrivateWitness,
        stewardSecret: Data,
        sealedAt: Date
    ) throws -> RuntimeOutput {
        let driver = sealPickDriver(
            deviceSecretHex: hex(witness.deviceSecret),
            stewardSecretHex: hex(stewardSecret),
            questionCommitmentHex: hex(round.questionCommitment),
            choice: witness.choice,
            now: sealedAt.compactTimestamp,
            deadline: round.sealDeadline.compactTimestamp
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
        questionCommitmentHex: String,
        choice: UInt8,
        now: UInt64,
        deadline: UInt64
    ) -> String {
        """
        (function(){
          const rt = __compactRuntime, C = __slipContract;
          const ADDR = '11'.repeat(32), CPK = { bytes: new Uint8Array(32) };
          const fromHex = (h) => new Uint8Array(h.match(/../g).map(x => Number.parseInt(x, 16)));
          const STEWARD = fromHex('\(stewardSecretHex)');
          const MEMBER = fromHex('\(deviceSecretHex)');
          const QUESTION = fromHex('\(questionCommitmentHex)');
          const NOW = \(now), DEADLINE = \(deadline);
          const w = (sk, p) => ({
            localSecretKey: ({ privateState }) => [privateState, sk],
            localPick:      ({ privateState }) => [privateState, p],
          });
          let state, priv;
          function call(sk, p, id, ...a) {
            const contract = new C.Contract(w(sk, p));
            const ctx = rt.createCircuitContext(ADDR, CPK, state, priv, undefined, undefined, NOW);
            ctx.currentQueryContext.block.secondsSinceEpoch = BigInt(NOW);
            const result = contract.impureCircuits[id](ctx, ...a);
            state = result.context.currentQueryContext.state;
            priv = result.context.currentPrivateState;
            return result;
          }
          const boot = new C.Contract(w(STEWARD, 0n));
          const initial = boot.initialState(rt.createConstructorContext(undefined, CPK));
          state = initial.currentContractState.data;
          priv = initial.currentPrivateState;
          call(STEWARD, 0n, 'enrollMember', C.pureCircuits.memberIdOf(MEMBER));
          call(STEWARD, 0n, 'createSlip', QUESTION, BigInt(DEADLINE));
          const pd = call(MEMBER, \(choice)n, 'sealPick').proofData;
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
