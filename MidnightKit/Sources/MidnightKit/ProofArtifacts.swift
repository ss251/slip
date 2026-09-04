import Foundation

/// Locates the compiled circuit, its proving key, and the BLS parameters.
///
/// Contract keys are ALWAYS bundled, never downloaded. Two reasons: a key fetched at
/// runtime is a supply-chain surface on the one artifact that defines what your proof
/// means, and the prover resolves keys by BASENAME from a flat directory, so a remote
/// layout would have to be flattened anyway.
///
/// Keys must be regenerated whenever the circuit is recompiled. A stale key against a
/// fresh circuit does not fail loudly at load — it fails on-chain as node error 115
/// (`InvalidProof`), long after the user thought they had sealed something.
public struct ProofArtifacts: Sendable {
    public let circuitsDirectory: URL
    public let keysDirectory: URL
    public let parametersDirectory: URL

    public init(circuitsDirectory: URL, keysDirectory: URL, parametersDirectory: URL) {
        self.circuitsDirectory = circuitsDirectory
        self.keysDirectory = keysDirectory
        self.parametersDirectory = parametersDirectory
    }

    /// The default layout: everything ships in the app bundle.
    ///
    /// Reading these from anywhere outside the sandbox is a mistake we already made
    /// once — a host path blocks forever in `open()` on device, at 0% CPU, with no
    /// crash and no timeout. It looks exactly like a pathologically slow prover.
    public static func bundled(_ bundle: Bundle = .main) -> ProofArtifacts {
        let root = bundle.resourceURL ?? bundle.bundleURL
        return ProofArtifacts(
            circuitsDirectory: root.appendingPathComponent("zkir"),
            keysDirectory: root.appendingPathComponent("keys"),
            parametersDirectory: root
        )
    }

    func circuit(_ name: String) -> URL { circuitsDirectory.appendingPathComponent("\(name).zkir") }
    func provingKey(_ name: String) -> URL { keysDirectory.appendingPathComponent("\(name).prover") }

    /// Fails early with a precise error rather than letting the FFI return a bare code.
    func validate(circuit name: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: circuit(name).path) else { throw MidnightKitError.circuitNotFound(name) }
        guard fm.fileExists(atPath: provingKey(name).path) else { throw MidnightKitError.provingKeyMissing(circuit: name) }
    }
}
