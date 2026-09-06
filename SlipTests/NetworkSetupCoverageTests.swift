import Foundation
import Testing
@testable import Slip

@Suite(.serialized)
struct NetworkSetupCoverageTests {
    private static let address = String(repeating: "aB", count: 32)

    @Test("relay preferences round-trip, remove an absent token, and clear only their own keys")
    func preferencesRoundTripAndClear() throws {
        let suite = "slip.tests.network-setup.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("preserve", forKey: "unrelated.preference")
        #expect(NetworkSetup.load(defaults: defaults) == nil)

        var setup = NetworkSetup(
            relayURL: try #require(URL(string: "http://relay.test:8787")),
            contractAddressHex: Self.address,
            relayToken: "synthetic-test-token"
        )
        setup.save(defaults: defaults)
        #expect(NetworkSetup.load(defaults: defaults) == setup)

        setup.relayToken = nil
        setup.save(defaults: defaults)
        #expect(defaults.object(forKey: NetworkSetup.tokenKey) == nil)
        #expect(NetworkSetup.load(defaults: defaults) == setup)

        NetworkSetup.clear(defaults: defaults)
        #expect(NetworkSetup.load(defaults: defaults) == nil)
        #expect(defaults.object(forKey: NetworkSetup.relayKey) == nil)
        #expect(defaults.object(forKey: NetworkSetup.contractKey) == nil)
        #expect(defaults.object(forKey: NetworkSetup.tokenKey) == nil)
        #expect(defaults.string(forKey: "unrelated.preference") == "preserve")
    }

    @Test("incomplete or malformed stored relay setup keeps the local flow selected")
    func rejectsMalformedPreferences() throws {
        let suite = "slip.tests.network-invalid.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("http://relay.test", forKey: NetworkSetup.relayKey)
        #expect(NetworkSetup.load(defaults: defaults) == nil)
        defaults.set(String(repeating: "g", count: 64), forKey: NetworkSetup.contractKey)
        #expect(NetworkSetup.load(defaults: defaults) == nil)
        defaults.set(Self.address, forKey: NetworkSetup.contractKey)
        defaults.set("http://[", forKey: NetworkSetup.relayKey)
        #expect(NetworkSetup.load(defaults: defaults) == nil)
    }

    @Test("launch setup rejects missing values and invalid addresses while preserving its optional token")
    func launchArgumentBoundaries() {
        let invalid: [[String]] = [
            [], ["--relay"], ["--relay", "http://relay.test"],
            ["--relay", "http://relay.test", "--contract"],
            ["--relay", "http://[", "--contract", Self.address],
            ["--relay", "http://relay.test", "--contract", String(repeating: "g", count: 64)],
            ["--relay", "http://relay.test", "--contract", String(Self.address.dropLast())]
        ]
        for arguments in invalid {
            #expect(NetworkSetup.fromLaunchArguments(arguments) == nil)
        }
        let required = ["--relay", "http://relay.test", "--contract", Self.address]
        #expect(NetworkSetup.fromLaunchArguments(required + ["--relay-token"])?.relayToken == nil)
        let setup = NetworkSetup.fromLaunchArguments(required + ["--relay-token", "synthetic-test-token"])
        #expect(setup?.contractAddressHex == Self.address)
        #expect(setup?.relayToken == "synthetic-test-token")
    }

    @Test("a malformed stored identity is replaced with one valid session identity")
    func malformedIdentityIsReplaced() throws {
        let store = MemorySecretStore(Data(repeating: 0xA5, count: 31))
        let replacement = try DeviceIdentity.secret(store: store)
        #expect(replacement.count == DeviceIdentity.secretByteCount)
        let replacementWasStored = try store.read() == replacement
        let sameIdentityWasReused = try DeviceIdentity.secret(store: store) == replacement
        #expect(replacementWasStored)
        #expect(sameIdentityWasReused)
    }

    @Test("identity read and write failures propagate instead of inventing a usable identity")
    func identityStoreFailuresPropagate() {
        #expect(throws: StoreFailure.read) {
            _ = try DeviceIdentity.secret(store: FailingStore(failure: .read))
        }
        #expect(throws: StoreFailure.write) {
            _ = try DeviceIdentity.secret(store: FailingStore(failure: .write))
        }
    }

    private enum StoreFailure: Error { case read, write }

    private struct FailingStore: SecretStore {
        let failure: StoreFailure
        func read() throws -> Data? {
            if failure == .read { throw failure }
            return nil
        }
        func write(_ secret: Data) throws { throw failure }
    }
}
