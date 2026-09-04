import Foundation
import MidnightKit
import Testing
@testable import Slip

@Suite(.serialized)
struct LocalSealingServiceTests {
    private enum SealAttempt: Sendable {
        case success(LocalSealReceipt)
        case failure(AppSealError)
    }

    @Test("both legal picks execute and produce a real local proof", arguments: [UInt8(0), UInt8(1)])
    func realProof(choice: UInt8) async throws {
        let service = Self.makeService()

        let receipt = try await service.seal(choice: choice)

        #expect(receipt.proofBytes > 0)
        #expect(receipt.proofData.count == receipt.proofBytes)
        #expect(receipt.executeDuration > .zero)
        #expect(receipt.keyLoadDuration > .zero)
        #expect(receipt.proveDuration > .zero)
        let commitment = try #require(receipt.commitment)
        #expect(commitment.count == 32)
    }

    @Test("a repeated seal returns the existing receipt without another proof")
    func repeatReturnsExistingReceipt() async throws {
        let service = Self.makeService()
        let first = try await service.seal(choice: 0)

        // Even a later conflicting selection cannot replace an already sealed pick.
        let repeated = try await service.seal(choice: 1)

        #expect(repeated == first)
    }

    @Test("simultaneous seal requests do not start two proofs")
    func simultaneousSealIsRejected() async {
        let service = Self.makeService()

        let attempts = await withTaskGroup(of: SealAttempt.self, returning: [SealAttempt].self) { group in
            group.addTask { await Self.attempt(service: service, choice: 0) }
            group.addTask { await Self.attempt(service: service, choice: 1) }

            var results: [SealAttempt] = []
            for await result in group { results.append(result) }
            return results
        }

        let receipts = attempts.compactMap { attempt -> LocalSealReceipt? in
            guard case .success(let receipt) = attempt else { return nil }
            return receipt
        }
        let failures = attempts.compactMap { attempt -> AppSealError? in
            guard case .failure(let error) = attempt else { return nil }
            return error
        }

        #expect(receipts.count == 1)
        #expect(failures == [.sealInProgress])
    }

    @Test("missing bundled artifacts surface a named, sanitized app error")
    func missingArtifactsAreNamed() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-proof-artifacts-\(UUID().uuidString)", isDirectory: true)
        let service = LocalSealingService(artifacts: ProofArtifacts(
            circuitsDirectory: missing.appendingPathComponent("zkir", isDirectory: true),
            keysDirectory: missing.appendingPathComponent("keys", isDirectory: true),
            parametersDirectory: missing.appendingPathComponent("params", isDirectory: true)
        ))

        await #expect(throws: AppSealError.circuitNotFound) {
            _ = try await service.seal(choice: 0)
        }
    }

    @Test("out-of-range picks never enter the runtime")
    func invalidChoiceIsRejected() async {
        let service = Self.makeService()

        await #expect(throws: AppSealError.invalidChoice) {
            _ = try await service.seal(choice: 2)
        }
    }

    private static func makeService() -> LocalSealingService {
        LocalSealingService(artifacts: LocalSealingService.bundledArtifacts())
    }

    private static func attempt(service: LocalSealingService, choice: UInt8) async -> SealAttempt {
        do {
            return .success(try await service.seal(choice: choice))
        } catch let error as AppSealError {
            return .failure(error)
        } catch {
            return .failure(.unexpected)
        }
    }
}
