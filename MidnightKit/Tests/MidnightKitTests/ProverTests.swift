import Testing
import Foundation
@testable import MidnightKit

@Suite(.serialized)
struct ProverTests {

    @Test("the linked archive is MidnightKit's, not an earlier spike library")
    func linkedLibraryIsOurs() {
        #expect(Prover.linkedLibraryIsMidnightKit())
    }

    @Test("a missing circuit fails with a named error, not a bare FFI code")
    func missingCircuitIsNamed() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let prover = Prover(artifacts: ProofArtifacts(
            circuitsDirectory: tmp, keysDirectory: tmp, parametersDirectory: tmp
        ))
        await #expect(throws: MidnightKitError.circuitNotFound("sealPick")) {
            _ = try await prover.prove(circuit: "sealPick", preimage: tmp.appendingPathComponent("x.bin"))
        }
    }

    @Test("a circuit present without its proving key is distinguishable from a missing circuit")
    func missingKeyIsItsOwnError() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mk-\(UUID().uuidString)")
        let zkir = tmp.appendingPathComponent("zkir")
        try FileManager.default.createDirectory(at: zkir, withIntermediateDirectories: true)
        try Data().write(to: zkir.appendingPathComponent("sealPick.zkir"))

        let prover = Prover(artifacts: ProofArtifacts(
            circuitsDirectory: zkir, keysDirectory: tmp, parametersDirectory: tmp
        ))
        // Distinct from circuitNotFound on purpose: a stale or absent key is the failure
        // that surfaces on-chain as node error 115 (InvalidProof), and collapsing the two
        // would send someone hunting for a missing circuit that is right there.
        await #expect(throws: MidnightKitError.provingKeyMissing(circuit: "sealPick")) {
            _ = try await prover.prove(circuit: "sealPick", preimage: tmp.appendingPathComponent("x.bin"))
        }
        try? FileManager.default.removeItem(at: tmp)
    }
}
