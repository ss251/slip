import Foundation
import MidnightKit
import Testing
@testable import Slip

@Suite(.serialized)
struct LocalSealingServiceTests {
    private enum SealAttempt: Sendable {
        case success(LocalSealResult)
        case failure(AppSealError)
    }

    @Test("both legal picks execute and produce a real round-bound proof", arguments: [UInt8(0), UInt8(1)])
    func realProof(choice: UInt8) async throws {
        let service = Self.makeService()
        let round = Self.makeRound()

        let result = try await service.seal(round: round, choice: choice)

        #expect(result.receipt.roundID == round.id)
        #expect(result.receipt.questionCommitment == round.questionCommitment)
        #expect(result.receipt.questionCommitment.count == 32)
        #expect(result.receipt.proofBytes > 0)
        #expect(result.receipt.proofData.count == result.receipt.proofBytes)
        #expect(result.receipt.executeDuration > .zero)
        #expect(result.receipt.keyLoadDuration > .zero)
        #expect(result.receipt.proveDuration > .zero)
        let commitment = try #require(result.receipt.commitment)
        #expect(commitment.count == 32)

        let privateMetadataMatches = result.privateDisplay.roundID == round.id
            && result.privateDisplay.question == round.question
            && result.privateDisplay.sides == round.sides
            && result.privateDisplay.crewName == round.crewName
            && result.privateDisplay.sealDeadline == round.sealDeadline
        let privateChoiceMatches = result.privateDisplay.selectedSide == (choice == 1 ? "Yes" : "No")
            && result.privateDisplay.selectedSideIndex == (choice == 1 ? 0 : 1)
        #expect(privateMetadataMatches)
        #expect(privateChoiceMatches)
    }

    @Test("a repeated round returns its immutable original result")
    func repeatReturnsExistingResult() async throws {
        let service = Self.makeService()
        let round = Self.makeRound()
        let first = try await service.seal(round: round, choice: 0)

        // A later conflicting UI selection cannot replace or relabel the sealed pick.
        let repeated = try await service.seal(round: round, choice: 1)

        let exactResultWasReused = repeated == first
        let originalPrivatePickWasPreserved = repeated.privateDisplay.selectedSide == "No"
            && repeated.privateDisplay.selectedSideIndex == 1
        #expect(exactResultWasReused)
        #expect(originalPrivatePickWasPreserved)

        let edited = LocalRound(
            id: round.id,
            question: "A relabelled question?",
            sides: round.sides,
            crewName: round.crewName,
            createdAt: round.createdAt,
            sealDeadline: round.sealDeadline
        )
        await #expect(throws: AppSealError.roundIdentityConflict) {
            _ = try await service.seal(round: edited, choice: 0)
        }
    }

    @Test("simultaneous seal requests do not start two proofs")
    func simultaneousSealIsRejected() async {
        let service = Self.makeService()
        let round = Self.makeRound()

        let attempts = await withTaskGroup(of: SealAttempt.self, returning: [SealAttempt].self) { group in
            group.addTask { await Self.attempt(service: service, round: round, choice: 0) }
            group.addTask { await Self.attempt(service: service, round: round, choice: 1) }

            var results: [SealAttempt] = []
            for await result in group { results.append(result) }
            return results
        }

        let results = attempts.compactMap { attempt -> LocalSealResult? in
            guard case .success(let result) = attempt else { return nil }
            return result
        }
        let failures = attempts.compactMap { attempt -> AppSealError? in
            guard case .failure(let error) = attempt else { return nil }
            return error
        }

        #expect(results.count == 1)
        #expect(failures == [.sealInProgress])
    }

    @Test("a new local round cannot reuse the prior round result")
    func newRoundDoesNotReuseResult() async throws {
        let service = Self.makeService()
        let firstRound = Self.makeRound(question: "First local question?")
        let secondRound = Self.makeRound(question: "Second local question?")

        let first = try await service.seal(round: firstRound, choice: 1)
        let second = try await service.seal(round: secondRound, choice: 0)

        #expect(first.receipt.roundID != second.receipt.roundID)
        #expect(first.receipt.questionCommitment != second.receipt.questionCommitment)
        let privateDisplaysMatchTheirRounds = first.privateDisplay.question == "First local question?"
            && second.privateDisplay.question == "Second local question?"
            && first.privateDisplay.selectedSide == "Yes"
            && second.privateDisplay.selectedSide == "No"
        #expect(privateDisplaysMatchTheirRounds)
    }

    @Test("canonical commitment changes when bound public metadata changes")
    func publicMetadataIsBound() {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_788_600_000)
        let deadline = createdAt.addingTimeInterval(3_600)
        let base = LocalRound(
            id: id,
            question: "Will it rain?",
            sides: ["Yes", "No"],
            crewName: "Saturday crew",
            createdAt: createdAt,
            sealDeadline: deadline
        )
        let questionEdit = LocalRound(
            id: id,
            question: "Will it snow?",
            sides: base.sides,
            crewName: base.crewName,
            createdAt: createdAt,
            sealDeadline: deadline
        )
        let sideEdit = LocalRound(
            id: id,
            question: base.question,
            sides: ["Probably", "Unlikely"],
            crewName: base.crewName,
            createdAt: createdAt,
            sealDeadline: deadline
        )
        let crewEdit = LocalRound(
            id: id,
            question: base.question,
            sides: base.sides,
            crewName: "Sunday crew",
            createdAt: createdAt,
            sealDeadline: deadline
        )
        let deadlineEdit = LocalRound(
            id: id,
            question: base.question,
            sides: base.sides,
            crewName: base.crewName,
            createdAt: createdAt,
            sealDeadline: deadline.addingTimeInterval(1)
        )

        #expect(base.questionCommitment.count == 32)
        #expect(base.questionCommitment != questionEdit.questionCommitment)
        #expect(base.questionCommitment != sideEdit.questionCommitment)
        #expect(base.questionCommitment != crewEdit.questionCommitment)
        #expect(base.questionCommitment != deadlineEdit.questionCommitment)
    }

    @Test("missing bundled artifacts surface a named, sanitized app error")
    func missingArtifactsAreNamed() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-proof-artifacts-\(UUID().uuidString)", isDirectory: true)
        let service = Self.makeService(root: missing)

        await #expect(throws: AppSealError.circuitNotFound) {
            _ = try await service.seal(round: Self.makeRound(), choice: 0)
        }
    }

    @Test("missing universal parameters are named before runtime execution")
    func missingParametersAreNamed() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-proof-params-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let circuits = root.appendingPathComponent("zkir", isDirectory: true)
        let keys = root.appendingPathComponent("keys", isDirectory: true)
        let parameters = root.appendingPathComponent("params", isDirectory: true)
        try FileManager.default.createDirectory(at: circuits, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: keys, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: parameters, withIntermediateDirectories: true)
        try Data([0]).write(to: circuits.appendingPathComponent("sealPick.zkir"))
        try Data([0]).write(to: keys.appendingPathComponent("sealPick.prover"))

        let service = Self.makeService(root: root)
        await #expect(throws: AppSealError.parametersMissing) {
            _ = try await service.seal(round: Self.makeRound(), choice: 0)
        }
    }

    @Test("deadline preflight exactly mirrors the contract window")
    func deadlineBoundsMatchContract() async {
        let now = Date(timeIntervalSince1970: 1_788_600_000)

        #expect(LocalSealingService.deadlineError(for: now, relativeTo: now) == .sealDeadlinePassed)
        #expect(LocalSealingService.deadlineError(
            for: now.addingTimeInterval(300),
            relativeTo: now
        ) == .sealDeadlineTooSoon)
        #expect(LocalSealingService.deadlineError(
            for: now.addingTimeInterval(301),
            relativeTo: now
        ) == nil)
        #expect(LocalSealingService.deadlineError(
            for: now.addingTimeInterval(31_536_000),
            relativeTo: now
        ) == nil)
        #expect(LocalSealingService.deadlineError(
            for: now.addingTimeInterval(31_536_001),
            relativeTo: now
        ) == .sealDeadlineTooFar)
        let unrepresentableEndpoint = Date(timeIntervalSince1970: Double(UInt64.max))
        #expect(LocalSealingService.deadlineError(
            for: unrepresentableEndpoint,
            relativeTo: now
        ) == .sealDeadlinePassed)

        // Missing artifacts prove these public checks run before private execution.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadline-before-artifacts-\(UUID().uuidString)", isDirectory: true)
        let service = Self.makeService(root: missing)
        let tooSoon = Self.makeRound(createdAt: now, deadline: Date().addingTimeInterval(300))
        let tooFar = Self.makeRound(createdAt: now, deadline: Date().addingTimeInterval(31_536_600))
        await #expect(throws: AppSealError.sealDeadlineTooSoon) {
            _ = try await service.seal(round: tooSoon, choice: 0)
        }
        await #expect(throws: AppSealError.sealDeadlineTooFar) {
            _ = try await service.seal(round: tooFar, choice: 0)
        }
    }

    @Test("expired rounds and out-of-range picks never enter the runtime")
    func invalidInputIsRejected() async {
        let service = Self.makeService()
        let now = Date()
        let expired = Self.makeRound(createdAt: now.addingTimeInterval(-7_200), deadline: now.addingTimeInterval(-1))

        await #expect(throws: AppSealError.invalidChoice) {
            _ = try await service.seal(round: Self.makeRound(), choice: 2)
        }
        await #expect(throws: AppSealError.sealDeadlinePassed) {
            _ = try await service.seal(round: expired, choice: 0)
        }
    }

    private static func makeRound(
        question: String = "Will it rain on Saturday?",
        createdAt: Date = Date(),
        deadline: Date? = nil
    ) -> LocalRound {
        LocalRound(
            question: question,
            sides: ["Yes", "No"],
            crewName: "Saturday crew",
            createdAt: createdAt,
            sealDeadline: deadline ?? createdAt.addingTimeInterval(3_600)
        )
    }

    private static func makeService() -> LocalSealingService {
        LocalSealingService(artifacts: LocalSealingService.bundledArtifacts())
    }

    private static func makeService(root: URL) -> LocalSealingService {
        LocalSealingService(artifacts: ProofArtifacts(
            circuitsDirectory: root.appendingPathComponent("zkir", isDirectory: true),
            keysDirectory: root.appendingPathComponent("keys", isDirectory: true),
            parametersDirectory: root.appendingPathComponent("params", isDirectory: true)
        ))
    }

    private static func attempt(
        service: LocalSealingService,
        round: LocalRound,
        choice: UInt8
    ) async -> SealAttempt {
        do {
            return .success(try await service.seal(round: round, choice: choice))
        } catch let error as AppSealError {
            return .failure(error)
        } catch {
            return .failure(.unexpected)
        }
    }
}
