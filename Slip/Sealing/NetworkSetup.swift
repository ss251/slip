import Foundation
import Security

/// Where this device submits: a steward relay and the crew's deployed contract. Absent
/// on a fresh install (the app then runs the local, proof-only round).
struct NetworkSetup: Equatable, Sendable {
    let relayURL: URL
    let contractAddressHex: String

    static let relayKey = "slip.network.relayURL"
    static let contractKey = "slip.network.contractAddress"

    static func load(defaults: UserDefaults = .standard) -> NetworkSetup? {
        guard let url = defaults.string(forKey: relayKey).flatMap(URL.init(string:)),
              let address = defaults.string(forKey: contractKey), Self.isAddress(address) else { return nil }
        return NetworkSetup(relayURL: url, contractAddressHex: address)
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(relayURL.absoluteString, forKey: Self.relayKey)
        defaults.set(contractAddressHex, forKey: Self.contractKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: relayKey); defaults.removeObject(forKey: contractKey)
    }

    /// `--relay <url> --contract <64-hex>` (DEBUG launches, simctl).
    static func fromLaunchArguments(_ arguments: [String]) -> NetworkSetup? {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        guard let url = value("--relay").flatMap(URL.init(string:)), let address = value("--contract"), isAddress(address) else { return nil }
        return NetworkSetup(relayURL: url, contractAddressHex: address)
    }

    static func isAddress(_ hex: String) -> Bool { hex.count == 64 && Data(hex: hex) != nil }
}

/// Holds the device secret the contract identifies this member by. The secret is the
/// witness root: it is generated once, kept in the Keychain (this device only, after
/// first unlock), and never leaves the app. `memberIdOf(secret)` is the public identity.
protocol SecretStore: Sendable {
    func read() throws -> Data?
    func write(_ secret: Data) throws
}

enum DeviceIdentity {
    static let secretByteCount = 32

    static func secret(store: any SecretStore = KeychainSecretStore()) throws -> Data {
        if let existing = try store.read(), existing.count == secretByteCount { return existing }
        var bytes = Data(count: secretByteCount)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, secretByteCount, $0.baseAddress!) }
        guard status == errSecSuccess else { throw DeviceIdentityError.randomUnavailable }
        try store.write(bytes)
        return bytes
    }
}

enum DeviceIdentityError: Error, Equatable { case randomUnavailable, keychain(OSStatus) }

struct KeychainSecretStore: SecretStore {
    let service = "com.sailesh.slip.device-secret"
    let account = "member"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func read() throws -> Data? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw DeviceIdentityError.keychain(status) }
        return item as? Data
    }

    func write(_ secret: Data) throws {
        var add = query
        add[kSecValueData as String] = secret
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw DeviceIdentityError.keychain(status) }
    }
}

/// In-memory store for tests and previews.
final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private var value: Data?
    init(_ value: Data? = nil) { self.value = value }
    func read() throws -> Data? { value }
    func write(_ secret: Data) throws { value = secret }
}
