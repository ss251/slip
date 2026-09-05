import Foundation

/// Failures the prover can report. Codes mirror the Rust C-ABI's negative returns.
public enum MidnightKitError: Error, Equatable, Sendable {
    case circuitNotFound(String)
    case circuitUnreadable(String)
    case provingKeyMissing(circuit: String)
    case provingKeyUnreadable(circuit: String)
    case parametersMissing(k: Int)
    case preimageInvalid
    case proveFailed(code: Int32)
    case cancelled
    /// The contract runtime (JavaScriptCore) threw; message is the JS error.
    case runtime(String)
    /// `proofData` from the runtime did not deserialise into a proof preimage.
    case proofDataInvalid
    /// The transaction binding input was not a valid field element (hex).
    case bindingInputInvalid

    /// Maps the FFI's negative return codes. Anything unrecognised stays `proveFailed`
    /// with its raw code rather than being flattened into a generic error — a code we
    /// cannot name is information, not noise.
    static func from(code: Int32, circuit: String) -> MidnightKitError {
        switch code {
        case -10: return .circuitUnreadable(circuit)
        case -11: return .circuitNotFound(circuit)
        case -13: return .preimageInvalid
        case -14: return .preimageInvalid
        case -16: return .provingKeyMissing(circuit: circuit)
        case -17: return .provingKeyUnreadable(circuit: circuit)
        case -18: return .proofDataInvalid
        case -19: return .bindingInputInvalid
        default:  return .proveFailed(code: code)
        }
    }
}

extension MidnightKitError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .circuitNotFound(let c):      "circuit '\(c)' not found in the bundle"
        case .circuitUnreadable(let c):    "circuit '\(c)' could not be read"
        case .provingKeyMissing(let c):    "no proving key bundled for '\(c)'"
        case .provingKeyUnreadable(let c): "proving key for '\(c)' could not be read — recompiled circuit with a stale key?"
        case .parametersMissing(let k):    "missing BLS parameters bls_midnight_2p\(k)"
        case .preimageInvalid:             "proof preimage could not be decoded"
        case .proveFailed(let code):       "proving failed (code \(code))"
        case .cancelled:                   "proving was cancelled"
        case .runtime(let m):              "contract runtime error: \(m)"
        case .proofDataInvalid:            "proofData from the runtime could not be decoded into a preimage"
        case .bindingInputInvalid:         "transaction binding input is not a valid field element"
        }
    }
}
