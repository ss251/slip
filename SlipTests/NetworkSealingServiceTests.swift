import Foundation
import MidnightKit
import Testing
@testable import Slip

/// The network path, end to end on this device, against a stub relay that serves the
/// exported post-createSlip contract state (embedded so the test also runs on a phone).
@Suite(.serialized)
struct NetworkSealingServiceTests {
    static let fixtureState = Data(base64Encoded: "bWlkbmlnaHQ6Y29udHJhY3Qtc3RhdGVbdjZdOjkBAAgBAQQABAEAkGABvCrujoWizxu5Is7JYasHAZ37tvo9LX0aaQzObzyjnG8gAQQIBAEEDAgBBACQYAEJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCSABBBQEAQQYCAEEABhEEMWSaggEIAQBBCQIAQQAGESQFpRqCAQsBAEEMAgBBAAYRFC/lGoIBDgEAQQ8CAEEABhEEGiVaggERAQBBEgIAQQACAEIBFAEAQRUCAEEAJBgAf/ljRtFYCyTTeciaxfgb+0H97VmVyiK+QrMvuGOGhpPIAEABAAIXGAABGQIAQQEaJADBECAQpN0oZEynF8RASjMDbydr4q/dl9VPHydc3/PDvmZ0I8EbAQCBHAIAQQEYAQCBHgIAQQACEAIBIAEAQSECAEEAAgCAQSMBAEEkAgBBAAMQCABBJgEAQScCAEEQGAQHCg0QExYdHx8iIiUoGAIAjgIBKQIBDwEqAQDBKwABLAIAQQEtEQDBBk0QBBAEMQCABAAEEAAAAS4FQIDBP8BAo8EAQgBBAQBAAgBkGAB/+WNG0VgLJNN5yJrF+Bv7Qf3tWZXKIr5Csy+4Y4aGk8gAQABBAAAAQgBBAQBBAIEAQQAAAEIAQQEAQQCBAEEAAABCAEEBAEEAQQBCEAIAAEIAQQEAQQBBAEIQAgAAQgBBAQBBAEEAQgCAQABCAEEBAEABLwVAgME/wECQBBAEEARhEEMWSaggAAQgBBAQBBAEEARhEkBaUaggAAQgBBAQBBAEEARhEUL+UaggAAQgBBAQBBAEEARhEEGiVaggAAQgBBAQBBAEEAQgBCAABCAEEBAEEAgQBkAMEQIBCk3ShkTKcXxEBKMwNvJ2vir92X1U8fJ1zf88O+ZnQAEwBUCAwT/AQIBBAMEAQgEPAgBBAEEAQgBAQABCAI4QAEEAAABCAEEBAEEAQQBkGABvCrujoWizxu5Is7JYasHAZ37tvo9LX0aaQzObzyjnG8gAQABCAEEBAEEAQQBkGABCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkgAQABCAEEAAAsKGNyZWF0ZVNsaXAIyGAABMwIAQQE0JADBD+APGkRA2yruGX1sXo0V5WcnqcbiIsjteItOASNkCTTnBAANDBlbnJvbGxNZW1iZXII2GAABNwIAQQE4JADBD+AMe2MKzWCYr+ToHb8c6FjFvxwV9hu97XFAc/ILhIzCWAAJCBzZWFsUGljawjoYAAE7AgBBATwjAMEPnwXawrCum5umFthMYn1d4utcElN1u9Ydw1IdctgppLDABwYcmV2ZWFsCPhgAAT8CAEEBAEBjAMEPnz7rEtQjGQ45MQ/Kj4zokt20sgVkKpJh4Cd4mqBLO+0QGBgYGBg9GBgYGBgYGBgBQFgCAIIACAcZGlzcHV0ZQgNAWAABBEBCAEEBBUBjAMEPny7Y8S+nBhDsoGvK3uLBMOQ30tsnBWNl2g82MDczwS8ABwYc2V0dGxlCB0BYAAEIQEIAQQEJQGMAwQ+fPxW2XmqbjAg9kRctxQqe6OLsLRfxvG17S2uck1cPfZAYGBgYGAZAWBgYCkBYGBgYGBgCAIIQGDUYGDkYGBgCQFgLQFgYGBgYAgCGBSoYMQxAWAQAwAEAA==")!
    static let address = String(repeating: "11", count: 32)

    final class StubRelay: StewardRelay, @unchecked Sendable {
        var submitted: [Data] = []
        var confirmations = 0
        func context(for contractAddressHex: String) async throws -> NetworkContext {
            NetworkContext(contractAddressHex: contractAddressHex, contractState: NetworkSealingServiceTests.fixtureState, blockTime: 1_788_000_600)
        }
        func submit(provedTransaction: Data) async throws -> SubmissionReceipt {
            submitted.append(provedTransaction); return SubmissionReceipt(txID: "0xstub\(submitted.count)")
        }
        func confirm(commitmentHex: String) async throws -> ConfirmationStatus { confirmations += 1; return .confirmed }
    }

    static func service(relay: StubRelay) -> NetworkSealingService {
        NetworkSealingService(relay: relay, prover: Prover(artifacts: LocalSealingService.bundledArtifacts()),
                              contractAddressHex: address, deviceSecret: Data(repeating: 2, count: 32))
    }

    @Test("the member id is the contract's own memberIdOf(secret): 32 bytes, deterministic, secret-dependent")
    func memberID() async throws {
        let a = try await Self.service(relay: StubRelay()).memberIDHex()
        let again = try await Self.service(relay: StubRelay()).memberIDHex()
        let other = try await NetworkSealingService(relay: StubRelay(), prover: Prover(artifacts: LocalSealingService.bundledArtifacts()),
                                                    contractAddressHex: Self.address, deviceSecret: Data(repeating: 3, count: 32)).memberIDHex()
        #expect(Data(hex: a)?.count == 32)
        #expect(a == again)
        #expect(a != other)
    }

    @Test("seal executes against the live state, assembles a proved tx on device, submits it and confirms")
    func sealSubmitsProvedTransaction() async throws {
        let relay = StubRelay()
        let service = Self.service(relay: relay)
        let receipt = try await service.seal(choice: 1)
        print("NETWORK SEAL execute \(receipt.executeDuration) assemble+prove \(receipt.assembleDuration) tx \(receipt.transactionBytes) bytes")
        #expect(receipt.commitment.count == 32)
        #expect(receipt.transactionBytes > 4480)
        #expect(relay.submitted.count == 1 && relay.submitted[0].count == receipt.transactionBytes)
        #expect(String(decoding: relay.submitted[0].prefix(20), as: UTF8.self).hasPrefix("midnight:transaction"))
        // What the relay received contains no witness bytes: the device secret pattern is absent.
        #expect(relay.submitted[0].range(of: Data(repeating: 2, count: 32)) == nil)
        #expect(try await service.confirmation(of: receipt) == .confirmed)
        #expect(relay.confirmations == 1)
    }

    /// The relay is the one party that talks to this device and is not the device. Its
    /// `address` reaches a JavaScript string literal that also holds the device secret and
    /// the pick, so a quote-bearing address would be script injection inside the witness
    /// scope. Nothing gets proved or submitted when it is not plain lowercase hex.
    final class HostileRelay: StewardRelay, @unchecked Sendable {
        let address: String
        var submitted = 0
        init(address: String) { self.address = address }
        func context(for contractAddressHex: String) async throws -> NetworkContext {
            NetworkContext(contractAddressHex: address, contractState: NetworkSealingServiceTests.fixtureState, blockTime: 1_788_000_600)
        }
        func submit(provedTransaction: Data) async throws -> SubmissionReceipt {
            submitted += 1; return SubmissionReceipt(txID: "0xhostile")
        }
        func confirm(commitmentHex: String) async throws -> ConfirmationStatus { .confirmed }
    }

    @Test("a relay cannot smuggle script into the sealing driver through the contract address")
    func hostileRelayAddressIsRejected() async throws {
        let injections = [
            "'; throw new Error(MEMBER.join(',')); //",           // exfiltrate the device secret
            String(repeating: "11", count: 31) + "1'",            // right length, one quote
            String(repeating: "11", count: 32) + "1",             // too long
            String(repeating: "11", count: 31),                   // too short
            String(repeating: "1A", count: 32),                   // uppercase
            String(repeating: "zz", count: 32),                   // not hex
            String(repeating: "１", count: 64),                    // full-width digits
            ""
        ]
        for address in injections {
            let relay = HostileRelay(address: address)
            let service = NetworkSealingService(relay: relay, prover: Prover(artifacts: LocalSealingService.bundledArtifacts()),
                                                contractAddressHex: Self.address, deviceSecret: Data(repeating: 2, count: 32))
            await #expect(throws: NetworkSealError.relayContextRejected, "address \(address) should be refused") {
                _ = try await service.seal(choice: 1)
            }
            #expect(relay.submitted == 0)
        }
    }

    @Test("an invalid choice never reaches the relay")
    func invalidChoice() async throws {
        let relay = StubRelay()
        await #expect(throws: NetworkSealError.invalidChoice) { _ = try await Self.service(relay: relay).seal(choice: 2) }
        #expect(relay.submitted.isEmpty)
    }
}
