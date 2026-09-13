import Foundation
import MidnightKit

/// A pick sealed on this device and submitted to the network by the steward relay.
struct NetworkSealReceipt: Sendable, Equatable {
    let commitment: Data
    let txID: String
    /// The submit timed out; the tx may be on-chain. Resolve via confirmation().
    let submitPending: Bool
    let executeDuration: Duration
    let assembleDuration: Duration
    let transactionBytes: Int
}

enum NetworkSealError: Error, Equatable, Sendable {
    case invalidBlockTime
    case invalidChoice
    case commitmentUnavailable
    case sealInProgress
    /// The relay answered with a contract address that is not 64 lowercase hex characters.
    case relayContextRejected
}

/// The network path. Everything the steward relay learns is public: the member id (a
/// hash of the device secret), the proved transaction (proof + public transcript), and
/// which commitment to watch. The device secret, the pick and the private transcript stay
/// inside this actor; the transaction is assembled and proved in process by MidnightKit.
actor NetworkSealingService {
    private let relay: any StewardRelay
    private let prover: Prover
    private let contractAddressHex: String
    private let networkID: String
    private let deviceSecret: Data
    private var sealing = false
    private static let ttlSeconds: UInt64 = 1_800
    // The driver creates a JavaScript Number before converting block time to BigInt.
    private static let maximumExactJavaScriptInteger: UInt64 = 9_007_199_254_740_991

    init(relay: any StewardRelay, prover: Prover, contractAddressHex: String, networkID: String = "undeployed", deviceSecret: Data) {
        precondition(deviceSecret.count == 32, "device secret must be 32 bytes")
        self.relay = relay; self.prover = prover; self.contractAddressHex = contractAddressHex
        self.networkID = networkID; self.deviceSecret = deviceSecret
    }

    /// Public member id the steward enrols: `memberIdOf(secret)` computed by the contract's
    /// own pure circuit, so it cannot drift from what `sealPick` will derive.
    func memberIDHex() throws -> String {
        let rt = try ContractRuntime()
        return try rt.evaluate("""
        (function(){ const C = __slipContract;
          const fromHex = (h) => new Uint8Array(h.match(/../g).map(x => Number.parseInt(x, 16)));
          return Array.from(C.pureCircuits.memberIdOf(fromHex('\(deviceSecret.hexString)'))).map(b => b.toString(16).padStart(2,'0')).join(''); })()
        """)
    }

    func seal(choice: UInt8) async throws -> NetworkSealReceipt {
        guard choice == 0 || choice == 1 else { throw NetworkSealError.invalidChoice }
        guard !sealing else { throw NetworkSealError.sealInProgress }
        sealing = true; defer { sealing = false }

        let context = try await relay.context(for: contractAddressHex)
        // Reject before private execution. This also makes the later TTL addition safe.
        guard context.blockTime <= Self.maximumExactJavaScriptInteger - Self.ttlSeconds else {
            throw NetworkSealError.invalidBlockTime
        }
        // Defence in depth. The relay client already rejects a non-hex address, but this
        // value reaches a JavaScript string literal that also holds the device secret and
        // the pick, so the dangerous site refuses it too rather than trusting its caller.
        guard context.contractAddressHex.utf8.count == 64,
              context.contractAddressHex.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else { throw NetworkSealError.relayContextRejected }
        let started = ContinuousClock.now
        let rt = try ContractRuntime()
        let stateExpr = try rt.loadContractState(context.contractState)
        let proofData = try rt.evaluate(Self.sealPickDriver(
            stateExpression: stateExpr, addressHex: context.contractAddressHex,
            deviceSecretHex: deviceSecret.hexString, choice: choice, blockTime: context.blockTime))
        let executeDuration = ContinuousClock.now - started
        guard let commitment = Self.publicCommitment(from: proofData) else { throw NetworkSealError.commitmentUnavailable }

        let tx = try await prover.buildProvedCallTransaction(
            circuit: "sealPick", proofData: proofData, networkID: networkID,
            contractAddressHex: context.contractAddressHex, contractState: context.contractState,
            blockTime: context.blockTime, ttl: context.blockTime + Self.ttlSeconds)
        let receipt = try await relay.submit(provedTransaction: tx.data)
        return NetworkSealReceipt(commitment: commitment, txID: receipt.txID, submitPending: receipt.pending,
                                  executeDuration: executeDuration, assembleDuration: tx.duration,
                                  transactionBytes: tx.data.count)
    }

    func confirmation(of receipt: NetworkSealReceipt) async throws -> ConfirmationStatus {
        try await relay.confirm(commitmentHex: receipt.commitment.hexString)
    }

    /// `sealPick` publishes one 32-byte stored value: the commitment inserted into the seals
    /// map — the last `push` with `storage: true` in the public transcript. Bare-string ops
    /// ("lt", "member") sit alongside object ops, so the transcript is `[Any]`.
    static func publicCommitment(from proofData: String) -> Data? {
        guard let root = try? JSONSerialization.jsonObject(with: Data(proofData.utf8)) as? [String: Any],
              let transcript = root["publicTranscript"] as? [Any] else { return nil }
        for op in transcript.reversed().compactMap({ $0 as? [String: Any] }) {
            guard let push = op["push"] as? [String: Any], push["storage"] as? Bool == true,
                  let value = push["value"] as? [String: Any], value["tag"] as? String == "cell",
                  let content = value["content"] as? [String: Any], let nested = content["value"] as? [Any],
                  let bytes = nested.first as? [NSNumber], bytes.count == 32 else { continue }
            return Data(bytes.map { UInt8(truncatingIfNeeded: $0.intValue) })
        }
        return nil
    }

    /// sealPick against the LIVE state. Mirrors contracts/test/export-preimage.mjs's call.
    private static func sealPickDriver(stateExpression: String, addressHex: String, deviceSecretHex: String, choice: UInt8, blockTime: UInt64) -> String { """
    (function(){
      const rt = __compactRuntime, C = __slipContract;
      const fromHex = (h) => new Uint8Array(h.match(/../g).map(x => Number.parseInt(x, 16)));
      const ADDR = '\(addressHex)', CPK = { bytes: new Uint8Array(32) };
      const MEMBER = fromHex('\(deviceSecretHex)');
      const w = { localSecretKey: ({ privateState }) => [privateState, MEMBER], localPick: ({ privateState }) => [privateState, \(choice)n] };
      const state = \(stateExpression);
      const c = new C.Contract(w);
      const ctx = rt.createCircuitContext(ADDR, CPK, state, undefined, undefined, undefined, \(blockTime));
      ctx.currentQueryContext.block.secondsSinceEpoch = BigInt(\(blockTime));
      const pd = c.impureCircuits.sealPick(ctx).proofData;
      const enc = (v) => JSON.parse(JSON.stringify(v, (_, x) =>
        typeof x === 'bigint' ? x.toString() : (x instanceof Uint8Array ? Array.from(x) : x)));
      return JSON.stringify({ input: enc(pd.input), output: enc(pd.output),
        publicTranscript: enc(pd.publicTranscript), privateTranscriptOutputs: enc(pd.privateTranscriptOutputs) });
    })()
    """ }
}
