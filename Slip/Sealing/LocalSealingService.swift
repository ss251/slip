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

/// One proof-producing Compact circuit in the app-only local round lifecycle.
/// Raw values intentionally match the compiler-emitted artifact basenames.
enum LocalProofStep: String, CaseIterable, Sendable, Equatable, Hashable {
    case createSlip
    case enrollMember
    case sealPick
    case reveal
    case settle
    case dispute

    fileprivate var parameterK: Int {
        switch self {
        case .createSlip, .enrollMember, .settle, .dispute: 13
        case .sealPick, .reveal: 14
        }
    }
}

/// Public measurements for one locally generated proof. Proof bytes themselves are
/// retained only where the existing seal receipt needs them; no proof preimage is kept.
struct LocalStepReceipt: Sendable, Equatable {
    let step: LocalProofStep
    let executeDuration: Duration
    let keyLoadDuration: Duration
    let proveDuration: Duration
    let proofBytes: Int
}

enum LocalRoundStage: String, Sendable, Equatable {
    case sealed
    case revealed
    case settled
    case disputed
}

/// Public state read from the replayed Compact ledger after the latest proven step.
/// Contract sentinel `2` maps to `nil`; sentinel `3` remains `3` in a disputed result.
struct LocalRoundResult: Sendable, Equatable {
    let roundID: UUID
    let round: LocalRound
    let stage: LocalRoundStage
    let revealedChoice: UInt8?
    let outcome: UInt8?
    let tallyYes: Int
    let tallyNo: Int
    let disputedBy: Data?
    let steps: [LocalStepReceipt]
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
    case roundNotFound
    case invalidRoundTransition
    case invalidOutcome
    case outcomeConflict
    case revealMismatch
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
        case .roundNotFound: "This local slip is unavailable"
        case .invalidRoundTransition: "This local slip isn’t ready for that step"
        case .invalidOutcome: "Outcome must be one of the two sides"
        case .outcomeConflict: "This local slip already has a different outcome"
        case .revealMismatch: "Reveal doesn’t match the sealed pick"
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
    private static let secretByteCount = 32
    private static let minimumSealWindow: UInt64 = 300
    private static let maximumSealWindow: UInt64 = 31_536_000
    private static let revealWindow: UInt64 = 86_400
    private static let settleOffset: UInt64 = revealWindow + 60
    private static let disputeOffset: UInt64 = revealWindow + 120
    private static let sealSequence: [LocalProofStep] = [.enrollMember, .createSlip, .sealPick]
    // Preserve the original seal-only preflight behavior first, then check every
    // artifact needed to complete the local lifecycle before generating a secret.
    private static let artifactPreflightOrder: [LocalProofStep] = [
        .sealPick, .enrollMember, .createSlip, .reveal, .settle, .dispute
    ]

    private struct PrivateWitness: Sendable {
        let deviceSecret: Data
        let choice: UInt8
    }

    private struct SealedRound: Sendable {
        let round: LocalRound
        let result: LocalSealResult
        let witness: PrivateWitness
        let stewardSecret: Data
        let sealedAt: Date
        var lifecycle: LocalRoundResult
        var settledOutcome: UInt8?
    }

    private struct RuntimeOutput: Sendable {
        let proofData: String
        let executeDuration: Duration
        let ledger: PublicLedgerSnapshot
    }

    private struct PublicLedgerSnapshot: Sendable {
        let status: UInt8
        let contractRoundID: UInt64
        let memberID: Data
        let questionCommitment: Data
        let sealDeadline: UInt64
        let revealDeadline: UInt64
        let settleDeadline: UInt64
        let disputeDeadline: UInt64
        let commitment: Data?
        let revealedChoice: UInt8?
        let tallyYes: Int
        let tallyNo: Int
        let outcome: UInt8
        let disputedBy: Data
        let memberIsEnrolled: Bool
    }

    private struct CompletedStep: Sendable {
        let execution: RuntimeOutput
        let proof: Prover.Proof

        var receipt: LocalStepReceipt {
            LocalStepReceipt(
                step: step,
                executeDuration: execution.executeDuration,
                keyLoadDuration: proof.keyLoadDuration,
                proveDuration: proof.proveDuration,
                proofBytes: proof.bytes
            )
        }

        let step: LocalProofStep
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
            var completed: [CompletedStep] = []
            for step in Self.sealSequence {
                let completedStep = try await prove(
                    step: step,
                    round: round,
                    witness: witness,
                    stewardSecret: stewardSecret,
                    sealedAt: sealedAt,
                    includeReveal: false,
                    settledOutcome: nil,
                    revealChoiceOverride: nil
                )
                try Self.validate(
                    completedStep.execution.ledger,
                    for: step,
                    round: round,
                    witnessChoice: choice,
                    includeReveal: false,
                    settledOutcome: nil,
                    expectedCommitment: nil
                )
                completed.append(completedStep)
            }
            guard let seal = completed.last, seal.step == .sealPick else {
                throw AppSealError.unexpected
            }
            let receipt = LocalSealReceipt(
                roundID: round.id,
                questionCommitment: round.questionCommitment,
                proofData: seal.proof.data,
                proofBytes: seal.proof.bytes,
                executeDuration: seal.execution.executeDuration,
                keyLoadDuration: seal.proof.keyLoadDuration,
                proveDuration: seal.proof.proveDuration,
                commitment: seal.execution.ledger.commitment
            )
            let result = LocalSealResult(receipt: receipt, privateDisplay: privateDisplay)
            let lifecycle = Self.makeResult(
                round: round,
                stage: .sealed,
                ledger: seal.execution.ledger,
                steps: completed.map(\.receipt)
            )
            sealedRounds[round.id] = SealedRound(
                round: round,
                result: result,
                witness: witness,
                stewardSecret: stewardSecret,
                sealedAt: sealedAt,
                lifecycle: lifecycle,
                settledOutcome: nil
            )
            activeRound = nil
            return result
        } catch {
            activeRound = nil
            throw Self.sanitized(error)
        }
    }

    func currentResult(roundID: UUID) -> LocalRoundResult? {
        sealedRounds[roundID]?.lifecycle
    }

    func reveal(roundID: UUID) async throws -> LocalRoundResult {
        try await reveal(roundID: roundID, choiceOverride: nil)
    }

    func settle(roundID: UUID, outcome: UInt8) async throws -> LocalRoundResult {
        guard outcome == 0 || outcome == 1 else { throw AppSealError.invalidOutcome }
        guard activeRound == nil else { throw AppSealError.sealInProgress }
        guard var sealed = sealedRounds[roundID] else { throw AppSealError.roundNotFound }

        if let existing = sealed.settledOutcome {
            guard existing == outcome else { throw AppSealError.outcomeConflict }
            return sealed.lifecycle
        }
        guard sealed.lifecycle.stage == .sealed || sealed.lifecycle.stage == .revealed else {
            throw AppSealError.invalidRoundTransition
        }

        activeRound = sealed.round
        do {
            let completed = try await prove(
                step: .settle,
                round: sealed.round,
                witness: sealed.witness,
                stewardSecret: sealed.stewardSecret,
                sealedAt: sealed.sealedAt,
                includeReveal: sealed.lifecycle.revealedChoice != nil,
                settledOutcome: outcome,
                revealChoiceOverride: nil
            )
            try Self.validate(
                completed.execution.ledger,
                for: .settle,
                round: sealed.round,
                witnessChoice: sealed.witness.choice,
                includeReveal: sealed.lifecycle.revealedChoice != nil,
                settledOutcome: outcome,
                expectedCommitment: sealed.result.receipt.commitment
            )
            sealed.settledOutcome = outcome
            sealed.lifecycle = Self.makeResult(
                round: sealed.round,
                stage: .settled,
                ledger: completed.execution.ledger,
                steps: sealed.lifecycle.steps + [completed.receipt]
            )
            sealedRounds[roundID] = sealed
            activeRound = nil
            return sealed.lifecycle
        } catch {
            activeRound = nil
            throw Self.sanitized(error)
        }
    }

    func dispute(roundID: UUID) async throws -> LocalRoundResult {
        guard activeRound == nil else { throw AppSealError.sealInProgress }
        guard var sealed = sealedRounds[roundID] else { throw AppSealError.roundNotFound }
        if sealed.lifecycle.stage == .disputed { return sealed.lifecycle }
        guard sealed.lifecycle.stage == .settled, let outcome = sealed.settledOutcome else {
            throw AppSealError.invalidRoundTransition
        }

        activeRound = sealed.round
        do {
            let completed = try await prove(
                step: .dispute,
                round: sealed.round,
                witness: sealed.witness,
                stewardSecret: sealed.stewardSecret,
                sealedAt: sealed.sealedAt,
                includeReveal: sealed.lifecycle.revealedChoice != nil,
                settledOutcome: outcome,
                revealChoiceOverride: nil
            )
            try Self.validate(
                completed.execution.ledger,
                for: .dispute,
                round: sealed.round,
                witnessChoice: sealed.witness.choice,
                includeReveal: sealed.lifecycle.revealedChoice != nil,
                settledOutcome: outcome,
                expectedCommitment: sealed.result.receipt.commitment
            )
            sealed.lifecycle = Self.makeResult(
                round: sealed.round,
                stage: .disputed,
                ledger: completed.execution.ledger,
                steps: sealed.lifecycle.steps + [completed.receipt]
            )
            sealedRounds[roundID] = sealed
            activeRound = nil
            return sealed.lifecycle
        } catch {
            activeRound = nil
            throw Self.sanitized(error)
        }
    }

    #if DEBUG
    /// A test-only adversarial path. It replays the accepted seal, flips only the
    /// reveal witness inside the real circuit, and never caches the rejected result.
    func rejectMismatchedReveal(roundID: UUID) async throws {
        guard let sealed = sealedRounds[roundID] else { throw AppSealError.roundNotFound }
        guard sealed.lifecycle.stage == .sealed else { throw AppSealError.invalidRoundTransition }
        let flipped: UInt8 = sealed.witness.choice == 0 ? 1 : 0
        _ = try await reveal(roundID: roundID, choiceOverride: flipped)
    }
    #endif

    private func reveal(roundID: UUID, choiceOverride: UInt8?) async throws -> LocalRoundResult {
        guard activeRound == nil else { throw AppSealError.sealInProgress }
        guard var sealed = sealedRounds[roundID] else { throw AppSealError.roundNotFound }
        if sealed.lifecycle.revealedChoice != nil { return sealed.lifecycle }
        guard sealed.lifecycle.stage == .sealed else { throw AppSealError.invalidRoundTransition }

        activeRound = sealed.round
        do {
            let completed = try await prove(
                step: .reveal,
                round: sealed.round,
                witness: sealed.witness,
                stewardSecret: sealed.stewardSecret,
                sealedAt: sealed.sealedAt,
                includeReveal: false,
                settledOutcome: nil,
                revealChoiceOverride: choiceOverride
            )
            try Self.validate(
                completed.execution.ledger,
                for: .reveal,
                round: sealed.round,
                witnessChoice: sealed.witness.choice,
                includeReveal: true,
                settledOutcome: nil,
                expectedCommitment: sealed.result.receipt.commitment
            )
            sealed.lifecycle = Self.makeResult(
                round: sealed.round,
                stage: .revealed,
                ledger: completed.execution.ledger,
                steps: sealed.lifecycle.steps + [completed.receipt]
            )
            sealedRounds[roundID] = sealed
            activeRound = nil
            return sealed.lifecycle
        } catch let error as MidnightKitError {
            activeRound = nil
            if case .runtime(let message) = error,
               message.contains("reveal does not match the seal") {
                throw AppSealError.revealMismatch
            }
            throw Self.sanitized(error)
        } catch {
            activeRound = nil
            throw Self.sanitized(error)
        }
    }

    /// Executes a full accepted prefix synchronously in a fresh JS runtime, releases
    /// that runtime, and only then suspends in `Prover`. The serialized proof preimage
    /// is held in memory for this call and is never logged, persisted, or returned.
    private func prove(
        step: LocalProofStep,
        round: LocalRound,
        witness: PrivateWitness,
        stewardSecret: Data,
        sealedAt: Date,
        includeReveal: Bool,
        settledOutcome: UInt8?,
        revealChoiceOverride: UInt8?
    ) async throws -> CompletedStep {
        let execution = try Self.execute(
            target: step,
            round: round,
            witness: witness,
            stewardSecret: stewardSecret,
            sealedAt: sealedAt,
            includeReveal: includeReveal,
            settledOutcome: settledOutcome,
            revealChoiceOverride: revealChoiceOverride
        )
        let proof = try await prover.prove(circuit: step.rawValue, proofData: execution.proofData)
        return CompletedStep(execution: execution, proof: proof, step: step)
    }

    /// Checks the exact app-bundle layout before private data enters the runtime. The
    /// native prover opens `bls_midnight_2p{k}` exactly, so both k=13 and k=14 files
    /// are required; a larger SRS is not an implicit substitute for a smaller one.
    private func preflightArtifacts() throws {
        let fileManager = FileManager.default
        var checkedParameters: Set<Int> = []
        for step in Self.artifactPreflightOrder {
            let circuit = artifacts.circuitsDirectory.appendingPathComponent("\(step.rawValue).zkir")
            let key = artifacts.keysDirectory.appendingPathComponent("\(step.rawValue).prover")
            guard fileManager.fileExists(atPath: circuit.path) else { throw AppSealError.circuitNotFound }
            guard fileManager.isReadableFile(atPath: circuit.path) else { throw AppSealError.circuitUnreadable }
            guard fileManager.fileExists(atPath: key.path) else { throw AppSealError.provingKeyMissing }
            guard fileManager.isReadableFile(atPath: key.path) else { throw AppSealError.provingKeyUnreadable }

            if checkedParameters.insert(step.parameterK).inserted {
                let parameters = artifacts.parametersDirectory
                    .appendingPathComponent("bls_midnight_2p\(step.parameterK)")
                guard fileManager.fileExists(atPath: parameters.path),
                      fileManager.isReadableFile(atPath: parameters.path)
                else { throw AppSealError.parametersMissing }
            }
        }
    }

    /// Reconstructs the accepted public/private state prefix and executes one target
    /// circuit without suspension. The `ContractRuntime` local is destroyed on return.
    private static func execute(
        target: LocalProofStep,
        round: LocalRound,
        witness: PrivateWitness,
        stewardSecret: Data,
        sealedAt: Date,
        includeReveal: Bool,
        settledOutcome: UInt8?,
        revealChoiceOverride: UInt8?
    ) throws -> RuntimeOutput {
        let driver = roundDriver(
            target: target,
            deviceSecretHex: hex(witness.deviceSecret),
            stewardSecretHex: hex(stewardSecret),
            questionCommitmentHex: hex(round.questionCommitment),
            sealedChoice: witness.choice,
            revealChoice: revealChoiceOverride ?? witness.choice,
            openedAt: sealedAt.compactTimestamp,
            deadline: round.sealDeadline.compactTimestamp,
            includeReveal: includeReveal,
            settledOutcome: settledOutcome
        )

        let started = ContinuousClock.now
        let payload = try ContractRuntime().evaluate(driver)
        let executeDuration = ContinuousClock.now - started
        return try parseRuntimeOutput(payload, executeDuration: executeDuration)
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

    private static func roundDriver(
        target: LocalProofStep,
        deviceSecretHex: String,
        stewardSecretHex: String,
        questionCommitmentHex: String,
        sealedChoice: UInt8,
        revealChoice: UInt8,
        openedAt: UInt64,
        deadline: UInt64,
        includeReveal: Bool,
        settledOutcome: UInt8?
    ) -> String {
        let targetCall: String
        switch target {
        case .enrollMember:
            targetCall = "targetResult = call(STEWARD, 0n, 'enrollMember', OPENED, MEMBER_ID);"
        case .createSlip:
            targetCall = """
            call(STEWARD, 0n, 'enrollMember', OPENED, MEMBER_ID);
            targetResult = call(STEWARD, 0n, 'createSlip', OPENED, QUESTION, BigInt(DEADLINE));
            """
        case .sealPick:
            targetCall = """
            call(STEWARD, 0n, 'enrollMember', OPENED, MEMBER_ID);
            call(STEWARD, 0n, 'createSlip', OPENED, QUESTION, BigInt(DEADLINE));
            targetResult = call(MEMBER, \(sealedChoice)n, 'sealPick', OPENED);
            """
        case .reveal:
            targetCall = """
            call(STEWARD, 0n, 'enrollMember', OPENED, MEMBER_ID);
            call(STEWARD, 0n, 'createSlip', OPENED, QUESTION, BigInt(DEADLINE));
            call(MEMBER, \(sealedChoice)n, 'sealPick', OPENED);
            targetResult = call(MEMBER, \(revealChoice)n, 'reveal', REVEAL_TIME);
            """
        case .settle:
            let reveal = includeReveal
                ? "call(MEMBER, \(sealedChoice)n, 'reveal', REVEAL_TIME);"
                : ""
            let outcome = settledOutcome ?? 0
            targetCall = """
            call(STEWARD, 0n, 'enrollMember', OPENED, MEMBER_ID);
            call(STEWARD, 0n, 'createSlip', OPENED, QUESTION, BigInt(DEADLINE));
            call(MEMBER, \(sealedChoice)n, 'sealPick', OPENED);
            \(reveal)
            targetResult = call(STEWARD, 0n, 'settle', SETTLE_TIME, \(outcome)n);
            """
        case .dispute:
            let reveal = includeReveal
                ? "call(MEMBER, \(sealedChoice)n, 'reveal', REVEAL_TIME);"
                : ""
            let outcome = settledOutcome ?? 0
            targetCall = """
            call(STEWARD, 0n, 'enrollMember', OPENED, MEMBER_ID);
            call(STEWARD, 0n, 'createSlip', OPENED, QUESTION, BigInt(DEADLINE));
            call(MEMBER, \(sealedChoice)n, 'sealPick', OPENED);
            \(reveal)
            call(STEWARD, 0n, 'settle', SETTLE_TIME, \(outcome)n);
            targetResult = call(MEMBER, \(sealedChoice)n, 'dispute', DISPUTE_TIME);
            """
        }

        return """
        (function(){
          const rt = __compactRuntime, C = __slipContract;
          const ADDR = '11'.repeat(32), CPK = { bytes: new Uint8Array(32) };
          const fromHex = (h) => new Uint8Array(h.match(/../g).map(x => Number.parseInt(x, 16)));
          const STEWARD = fromHex('\(stewardSecretHex)');
          const MEMBER = fromHex('\(deviceSecretHex)');
          const QUESTION = fromHex('\(questionCommitmentHex)');
          const OPENED = \(openedAt), DEADLINE = \(deadline);
          const REVEAL_TIME = DEADLINE;
          const SETTLE_TIME = DEADLINE + \(settleOffset);
          const DISPUTE_TIME = DEADLINE + \(disputeOffset);
          const w = (sk, p) => ({
            localSecretKey: ({ privateState }) => [privateState, sk],
            localPick:      ({ privateState }) => [privateState, p],
          });
          let state, priv;
          function call(sk, p, id, time, ...a) {
            const contract = new C.Contract(w(sk, p));
            const ctx = rt.createCircuitContext(ADDR, CPK, state, priv, undefined, undefined, time);
            ctx.currentQueryContext.block.secondsSinceEpoch = BigInt(time);
            const result = contract.impureCircuits[id](ctx, ...a);
            state = result.context.currentQueryContext.state;
            priv = result.context.currentPrivateState;
            return result;
          }
          const boot = new C.Contract(w(STEWARD, 0n));
          const initial = boot.initialState(rt.createConstructorContext(undefined, CPK));
          state = initial.currentContractState.data;
          priv = initial.currentPrivateState;
          const MEMBER_ID = C.pureCircuits.memberIdOf(MEMBER);
          let targetResult;
          \(targetCall)
          const pd = targetResult.proofData;
          const ledger = C.ledger(state);
          const encode = (value) => JSON.parse(JSON.stringify(value, (_, item) =>
            typeof item === 'bigint' ? item.toString() :
              (item instanceof Uint8Array ? Array.from(item) : item)));
          return JSON.stringify({
            proofData: JSON.stringify({
              input: encode(pd.input),
              output: encode(pd.output),
              publicTranscript: encode(pd.publicTranscript),
              privateTranscriptOutputs: encode(pd.privateTranscriptOutputs),
            }),
            ledger: {
              status: Number(ledger.status),
              contractRoundID: ledger.roundId.toString(),
              memberID: Array.from(MEMBER_ID),
              questionCommitment: Array.from(ledger.questionCommit),
              sealDeadline: ledger.sealDeadline.toString(),
              revealDeadline: ledger.revealDeadline.toString(),
              settleDeadline: ledger.settleDeadline.toString(),
              disputeDeadline: ledger.disputeDeadline.toString(),
              commitment: ledger.seals.member(MEMBER_ID)
                ? Array.from(ledger.seals.lookup(MEMBER_ID)) : null,
              revealedChoice: ledger.reveals.member(MEMBER_ID)
                ? Number(ledger.reveals.lookup(MEMBER_ID)) : null,
              tallyYes: ledger.tallyYes.toString(),
              tallyNo: ledger.tallyNo.toString(),
              outcome: Number(ledger.outcome),
              disputedBy: Array.from(ledger.disputedBy),
              memberIsEnrolled: ledger.crew.member(MEMBER_ID),
            },
          });
        })()
        """
    }

    private static func parseRuntimeOutput(
        _ payload: String,
        executeDuration: Duration
    ) throws -> RuntimeOutput {
        guard
            let root = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
            let proofData = root["proofData"] as? String,
            let ledger = root["ledger"] as? [String: Any],
            let status = uint8(ledger["status"]),
            let contractRoundID = uint64(ledger["contractRoundID"]),
            let memberID = bytes32(ledger["memberID"]),
            let questionCommitment = bytes32(ledger["questionCommitment"]),
            let sealDeadline = uint64(ledger["sealDeadline"]),
            let revealDeadline = uint64(ledger["revealDeadline"]),
            let settleDeadline = uint64(ledger["settleDeadline"]),
            let disputeDeadline = uint64(ledger["disputeDeadline"]),
            let tallyYesValue = uint64(ledger["tallyYes"]),
            let tallyNoValue = uint64(ledger["tallyNo"]),
            tallyYesValue <= UInt64(Int.max),
            tallyNoValue <= UInt64(Int.max),
            let outcome = uint8(ledger["outcome"]),
            let disputedBy = bytes32(ledger["disputedBy"]),
            let memberIsEnrolled = ledger["memberIsEnrolled"] as? Bool
        else { throw AppSealError.runtime }

        let commitment = try optionalBytes32(ledger["commitment"])
        let revealedChoice: UInt8?
        if ledger["revealedChoice"] is NSNull {
            revealedChoice = nil
        } else {
            guard let value = uint8(ledger["revealedChoice"]) else { throw AppSealError.runtime }
            revealedChoice = value
        }
        return RuntimeOutput(
            proofData: proofData,
            executeDuration: executeDuration,
            ledger: PublicLedgerSnapshot(
                status: status,
                contractRoundID: contractRoundID,
                memberID: memberID,
                questionCommitment: questionCommitment,
                sealDeadline: sealDeadline,
                revealDeadline: revealDeadline,
                settleDeadline: settleDeadline,
                disputeDeadline: disputeDeadline,
                commitment: commitment,
                revealedChoice: revealedChoice,
                tallyYes: Int(tallyYesValue),
                tallyNo: Int(tallyNoValue),
                outcome: outcome,
                disputedBy: disputedBy,
                memberIsEnrolled: memberIsEnrolled
            )
        )
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        if let string = value as? String { return UInt64(string) }
        if let number = value as? NSNumber, number.int64Value >= 0 {
            return UInt64(number.int64Value)
        }
        return nil
    }

    private static func uint8(_ value: Any?) -> UInt8? {
        guard let integer = uint64(value), integer <= UInt8.max else { return nil }
        return UInt8(integer)
    }

    private static func bytes32(_ value: Any?) -> Data? {
        guard let values = value as? [NSNumber], values.count == secretByteCount,
              values.allSatisfy({ (0...255).contains($0.intValue) })
        else { return nil }
        return Data(values.map { UInt8($0.intValue) })
    }

    private static func optionalBytes32(_ value: Any?) throws -> Data? {
        guard let value else { throw AppSealError.runtime }
        if value is NSNull { return nil }
        guard let bytes = bytes32(value) else { throw AppSealError.runtime }
        return bytes
    }

    private static func validate(
        _ ledger: PublicLedgerSnapshot,
        for step: LocalProofStep,
        round: LocalRound,
        witnessChoice: UInt8,
        includeReveal: Bool,
        settledOutcome: UInt8?,
        expectedCommitment: Data?
    ) throws {
        let emptyBytes = Data(repeating: 0, count: secretByteCount)
        if step == .enrollMember {
            guard ledger.status == 0, ledger.contractRoundID == 0,
                  ledger.memberIsEnrolled, ledger.outcome == 2,
                  ledger.questionCommitment == emptyBytes,
                  ledger.sealDeadline == 0, ledger.revealDeadline == 0,
                  ledger.settleDeadline == 0, ledger.disputeDeadline == 0,
                  ledger.commitment == nil, ledger.revealedChoice == nil,
                  ledger.tallyYes == 0, ledger.tallyNo == 0,
                  ledger.disputedBy == emptyBytes
            else { throw AppSealError.runtime }
            return
        }

        let deadline = round.sealDeadline.compactTimestamp
        let (revealDeadline, revealOverflow) = deadline.addingReportingOverflow(revealWindow)
        let (settleDeadline, settleOverflow) = revealDeadline.addingReportingOverflow(43_200)
        let (disputeDeadline, disputeOverflow) = settleDeadline.addingReportingOverflow(43_200)
        guard !revealOverflow, !settleOverflow, !disputeOverflow,
              ledger.contractRoundID == 1,
              ledger.questionCommitment == round.questionCommitment,
              ledger.sealDeadline == deadline,
              ledger.revealDeadline == revealDeadline,
              ledger.settleDeadline == settleDeadline,
              ledger.disputeDeadline == disputeDeadline,
              ledger.memberIsEnrolled
        else { throw AppSealError.runtime }

        switch step {
        case .enrollMember:
            throw AppSealError.runtime
        case .createSlip:
            guard ledger.status == 1, ledger.outcome == 2,
                  ledger.commitment == nil, ledger.revealedChoice == nil,
                  ledger.tallyYes == 0, ledger.tallyNo == 0,
                  ledger.disputedBy == emptyBytes
            else { throw AppSealError.runtime }
        case .sealPick:
            guard ledger.status == 1, ledger.outcome == 2,
                  ledger.commitment?.count == secretByteCount,
                  ledger.revealedChoice == nil,
                  ledger.tallyYes == 0, ledger.tallyNo == 0,
                  ledger.disputedBy == emptyBytes
            else { throw AppSealError.runtime }
        case .reveal:
            guard let expectedCommitment, ledger.status == 1, ledger.outcome == 2,
                  ledger.commitment == expectedCommitment,
                  ledger.revealedChoice == witnessChoice,
                  ledger.tallyYes == (witnessChoice == 1 ? 1 : 0),
                  ledger.tallyNo == (witnessChoice == 0 ? 1 : 0),
                  ledger.disputedBy == emptyBytes
            else { throw AppSealError.runtime }
        case .settle:
            guard let settledOutcome, let expectedCommitment, ledger.status == 2,
                  ledger.outcome == settledOutcome,
                  ledger.commitment == expectedCommitment,
                  ledger.revealedChoice == (includeReveal ? witnessChoice : nil),
                  ledger.tallyYes == (includeReveal && witnessChoice == 1 ? 1 : 0),
                  ledger.tallyNo == (includeReveal && witnessChoice == 0 ? 1 : 0),
                  ledger.disputedBy == emptyBytes
            else { throw AppSealError.runtime }
        case .dispute:
            guard let expectedCommitment, ledger.status == 3, ledger.outcome == 3,
                  ledger.commitment == expectedCommitment,
                  ledger.disputedBy == ledger.memberID,
                  ledger.revealedChoice == (includeReveal ? witnessChoice : nil),
                  ledger.tallyYes == (includeReveal && witnessChoice == 1 ? 1 : 0),
                  ledger.tallyNo == (includeReveal && witnessChoice == 0 ? 1 : 0)
            else { throw AppSealError.runtime }
        }
    }

    private static func makeResult(
        round: LocalRound,
        stage: LocalRoundStage,
        ledger: PublicLedgerSnapshot,
        steps: [LocalStepReceipt]
    ) -> LocalRoundResult {
        LocalRoundResult(
            roundID: round.id,
            round: round,
            stage: stage,
            revealedChoice: ledger.revealedChoice,
            outcome: ledger.outcome == 2 ? nil : ledger.outcome,
            tallyYes: ledger.tallyYes,
            tallyNo: ledger.tallyNo,
            disputedBy: stage == .disputed ? ledger.disputedBy : nil,
            steps: steps
        )
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
