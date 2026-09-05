import Foundation
import JavaScriptCore
import CSlipProve

/// Executes the compiled Compact contract on this device.
///
/// The contract's circuits are ordinary JavaScript emitted by the Compact compiler;
/// they run under JavaScriptCore against the Compact runtime (Kuira's extracted shim,
/// with our LOCAL PATCHES — grep the resource for that marker). Everything the runtime
/// used to delegate to WebAssembly — hashing, commitments, field arithmetic and the
/// ledger state machine — is served by eight native hooks backed by the same Rust
/// ledger code the network runs. The output is `proofData`: the exact preimage of a
/// zero-knowledge proof, byte-identical to what Node's runtime produces for the same
/// call (that identity is the gate in `ContractRuntimeTests`).
///
/// Not thread-safe: a `JSContext` belongs to the thread that made it. Own one per
/// actor and call it from there. `Prover` does exactly this.
public final class ContractRuntime {
    private let ctx: JSContext
    private var lastException: String?

    /// Loads the runtime and the bundled contract. Throws if any script fails to
    /// evaluate — a broken bundle must never present as an app that "just can't seal".
    public init(contractScript: URL = ContractRuntime.bundledContract) throws {
        guard let ctx = JSContext() else { throw MidnightKitError.runtime("JSContext unavailable") }
        self.ctx = ctx
        ctx.exceptionHandler = { [weak self] _, e in self?.lastException = e?.toString() }
        try load(Self.resource("buffer-polyfill.js"))
        installNatives()
        try load(Self.resource("polyfills.js"))
        try load(Self.resource("compact-runtime-iife.js"))
        try load(contractScript)
    }

    public static var bundledContract: URL { resource("slip-contract-iife.js") }

    private static func resource(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "JS")
            ?? Bundle.module.resourceURL!.appendingPathComponent(name)
    }

    private func load(_ url: URL) throws {
        let src = try String(contentsOf: url, encoding: .utf8)
        lastException = nil
        ctx.evaluateScript(src, withSourceURL: url)
        if let e = lastException { throw MidnightKitError.runtime("\(url.lastPathComponent): \(e)") }
    }

    /// Evaluates `script` and returns its result as a string. Circuit drivers return
    /// the `proofData` JSON this way; see `Prover.prove(circuit:proofData:)`.
    public func evaluate(_ script: String) throws -> String {
        lastException = nil
        let v = ctx.evaluateScript(script)
        if let e = lastException { throw MidnightKitError.runtime(e) }
        guard let v, !v.isUndefined else { throw MidnightKitError.runtime("script returned undefined") }
        return v.toString()
    }

    /// Loads a deployed contract's current state (tagged `ContractState` bytes from the
    /// indexer) into the runtime and returns a JS expression that evaluates to the charged
    /// state object a circuit driver passes to `createCircuitContext`. This is the network
    /// path: the phone executes against the live chain state, never a state it invented.
    public func loadContractState(_ tagged: Data) throws -> String {
        let handle = tagged.withUnsafeBytes { buf -> UInt64 in
            slip_state_from_tagged(buf.bindMemory(to: UInt8.self).baseAddress, buf.count)
        }
        guard handle != 0 else { throw MidnightKitError.runtime("contract state bytes did not decode") }
        // The runtime accepts ChargedState/ContractState/StateValue instances only (it type-checks
        // createCircuitContext's argument), and its query path reads the handle from the
        // ChargedState — so hand it a real ChargedState that carries our handle.
        return "((() => { const R = __compactRuntime; const cs = new R.ChargedState(R.StateValue.newNull()); cs._rustHandle = \(handle); return cs; })())"
    }

    // MARK: - Native hooks (names are the runtime's; grep `globalThis.__native_` in the shim)

    /// Copy a Rust `char*` result and free it.
    private static func take(_ p: UnsafeMutablePointer<CChar>?) -> String {
        guard let p else { return "{\"error\":\"native returned NULL\"}" }
        defer { slip_free_string(p) }
        return String(cString: p)
    }

    private func installNatives() {
        let ctx = self.ctx
        // JSON.stringify turns a Uint8Array into an object ({"0":1,…}); the runtime's own
        // JSON paths use this replacer, and the two raw-value hooks need it on our side.
        let stringifyFn = ctx.evaluateScript(
            "(v) => JSON.stringify(v, (k, x) => x instanceof Uint8Array ? Array.from(x) : x)")!
        let toUint8Arrays = ctx.evaluateScript("(s) => JSON.parse(s).map(a => new Uint8Array(a))")!
        func stringify(_ v: JSValue) -> String { stringifyFn.call(withArguments: [v]).toString() }

        let hashAligned: @convention(block) (String) -> String = { Self.take(slip_persistent_hash_aligned($0)) }
        let commit: @convention(block) (JSValue, JSValue, JSValue) -> JSValue = { align, value, opening in
            let out = Self.take(slip_persistent_commit(stringify(align), stringify(value), stringify(opening)))
            if out.hasPrefix("{") {   // {"error":…} — surface as a JS exception, not undefined
                ctx.evaluateScript("throw new Error(\(out.debugDescription))")
                return JSValue(undefinedIn: ctx)
            }
            return toUint8Arrays.call(withArguments: [out])
        }
        let transient: @convention(block) (JSValue) -> JSValue = { _ in
            // No circuit of ours uses transientHash; failing loudly beats a wrong hash.
            ctx.evaluateScript("throw new Error('transientHash is not provided by MidnightKit')")
            return JSValue(undefinedIn: ctx)
        }
        let bigToValue: @convention(block) (String) -> String = { Self.take(slip_bigint_to_value($0)) }
        let valueToBig: @convention(block) (String) -> String = { Self.take(slip_value_to_bigint($0)) }
        let createState: @convention(block) (String) -> String = { String(slip_state_create_with_nulls($0)) }
        let setOp: @convention(block) (String, String) -> Int32 = { slip_state_set_operation($0, $1) }
        let query: @convention(block) (String, String, String) -> String = { h, ops, blockSecs in
            Self.take(slip_contract_query(h, ops, UInt64(blockSecs) ?? 0))
        }
        ctx.setObject(hashAligned, forKeyedSubscript: "__native_persistentHash_aligned" as NSString)
        ctx.setObject(commit,      forKeyedSubscript: "__native_persistentCommit" as NSString)
        ctx.setObject(transient,   forKeyedSubscript: "__native_transientHash" as NSString)
        ctx.setObject(bigToValue,  forKeyedSubscript: "__native_bigIntToValue" as NSString)
        ctx.setObject(valueToBig,  forKeyedSubscript: "__native_valueToBigInt" as NSString)
        ctx.setObject(createState, forKeyedSubscript: "__native_stateCreateWithNulls" as NSString)
        ctx.setObject(setOp,       forKeyedSubscript: "__native_stateSetOperation" as NSString)
        ctx.setObject(query,       forKeyedSubscript: "__native_contractQuery" as NSString)
    }
}
