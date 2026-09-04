import Testing
import Foundation
@testable import MidnightKit

/// THE gate for on-device execution: the contract run under JavaScriptCore on this
/// device must produce `proofData` identical to what Node's runtime produces for the
/// same call, and that `proofData` must prove. Anything less than identical means the
/// phone is not executing the contract the network verifies against.
@Suite(.serialized)
struct ContractRuntimeTests {
    /// Mirrors contracts/test/export-preimage.mjs exactly, constants included.
    static let sealPickDriver = """
    (function(){
      const rt = __compactRuntime, C = __slipContract;
      const ADDR = '11'.repeat(32), CPK = { bytes: new Uint8Array(32) };
      const k = (b) => new Uint8Array(32).fill(b);
      const STEWARD = k(1), ALICE = k(2);
      const NOW = 1788000000, DEADLINE = NOW + 3600;
      const w = (sk, p) => ({
        localSecretKey: ({ privateState }) => [privateState, sk],
        localPick:      ({ privateState }) => [privateState, p],
      });
      let state, priv;
      function call(sk, p, id, t, ...a) {
        const c = new C.Contract(w(sk, p));
        const ctx = rt.createCircuitContext(ADDR, CPK, state, priv, undefined, undefined, t);
        ctx.currentQueryContext.block.secondsSinceEpoch = BigInt(t);
        const r = c.impureCircuits[id](ctx, ...a);
        state = r.context.currentQueryContext.state;
        priv = r.context.currentPrivateState;
        return r;
      }
      const boot = new C.Contract(w(STEWARD, 0n));
      const init = boot.initialState(rt.createConstructorContext(undefined, CPK));
      state = init.currentContractState.data;
      priv  = init.currentPrivateState;
      call(STEWARD, 0n, 'enrollMember', NOW, C.pureCircuits.memberIdOf(ALICE));
      call(STEWARD, 0n, 'createSlip', NOW + 10, new Uint8Array(32).fill(9), BigInt(DEADLINE));
      const pd = call(ALICE, 1n, 'sealPick', NOW + 600).proofData;
      const enc = (v) => JSON.parse(JSON.stringify(v, (_, x) =>
        typeof x === 'bigint' ? x.toString() : (x instanceof Uint8Array ? Array.from(x) : x)));
      return JSON.stringify({
        input: enc(pd.input), output: enc(pd.output),
        publicTranscript: enc(pd.publicTranscript), privateTranscriptOutputs: enc(pd.privateTranscriptOutputs),
      });
    })()
    """

    static func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
            ?? Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    /// Repo-local artifacts (contracts/build is produced by `compact compile`; params by
    /// the proof-server download). Simulator-only: reads host paths. Missing artifacts
    /// FAIL — a skipped gate is a gate that is not checking.
    static var artifacts: ProofArtifacts {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("contracts/build")
        return ProofArtifacts(
            circuitsDirectory: root.appendingPathComponent("zkir"),
            keysDirectory: root.appendingPathComponent("keys"),
            parametersDirectory: root.appendingPathComponent("params")
        )
    }

    @Test("the runtime and contract load with every native hook wired")
    func runtimeLoads() throws {
        let rt = try ContractRuntime()
        #expect(try rt.evaluate("Object.keys(__compactRuntime).length") != "0")
        #expect(try rt.evaluate("typeof __slipContract.Contract") == "function")
    }

    @Test("sealPick executed on device yields proofData identical to Node's, and it proves")
    func sealPickIsFaithfulAndProves() async throws {
        let rt = try ContractRuntime()
        let started = ContinuousClock.now
        let json = try rt.evaluate(Self.sealPickDriver)
        let executed = ContinuousClock.now - started

        let device = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! NSDictionary
        let golden = try JSONSerialization.jsonObject(with: Self.fixture("sealPick-proofdata.json")) as! NSDictionary
        #expect(device == golden, "on-device proofData differs from Node's — execution is not faithful")

        let prover = Prover(artifacts: Self.artifacts)
        let proof = try await prover.prove(circuit: "sealPick", proofData: json)
        print("""

        ===== MidnightKit: EXECUTE → PROVE, on device =====
        execute   : \(executed)
        identical : \(device == golden)
        pk load   : \(proof.keyLoadDuration)   prove: \(proof.proveDuration)
        proof     : \(proof.bytes) bytes (\(proof.data.count) returned)
        ==================================================

        """)
        #expect(proof.bytes == 4480)
        #expect(proof.data.count == proof.bytes)
    }
}
