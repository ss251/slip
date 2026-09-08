import Foundation
import Testing
@testable import Slip

@Suite(.serialized)
struct RoundInviteTests {
    static let contract = String(repeating: "ab", count: 32)

    static func invite(deadlineOffset: TimeInterval = 3600) -> RoundInvite {
        RoundInvite(
            relayURL: URL(string: "https://relay.test/steward")!,
            contractAddressHex: contract,
            roundID: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00CF4FC964FF")!,
            question: "Will it rain on Saturday?",
            sides: ["Yes", "No"],
            crewName: "Saturday crew",
            paletteKey: "saturday-crew",
            sealDeadline: Date(timeIntervalSince1970: 1_800_000_000).addingTimeInterval(deadlineOffset)
        )
    }

    static func now(before deadline: Date) -> Date { deadline.addingTimeInterval(-60) }

    @Test("an invite survives a round trip through its payload unchanged")
    func roundTripsThroughPayload() throws {
        let original = Self.invite()
        let decoded = try RoundInvite.decode(payload: try original.encodedPayload(),
                                             now: Self.now(before: original.sealDeadline))
        #expect(decoded == original)
    }

    @Test("an invite survives a round trip through its slip://join URL")
    func roundTripsThroughURL() throws {
        let original = Self.invite()
        let url = try original.inviteURL()
        #expect(url.scheme == "slip")
        #expect(url.host == "join")
        let decoded = try RoundInvite.decode(url: url, now: Self.now(before: original.sealDeadline))
        #expect(decoded == original)
    }

    @Test("the same invite encodes to the same payload every time")
    func encodingIsDeterministic() throws {
        let invite = Self.invite()
        let first = try invite.encodedPayload()
        for _ in 0..<8 { #expect(try invite.encodedPayload() == first) }
    }

    @Test("the payload is URL-safe and needs no escaping")
    func payloadIsURLSafe() throws {
        let payload = try Self.invite().encodedPayload()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        #expect(payload.unicodeScalars.allSatisfy(allowed.contains))
    }

    @Test("a truncated payload is rejected rather than half-parsed")
    func rejectsTruncatedPayload() throws {
        let payload = try Self.invite().encodedPayload()
        for keep in [payload.count / 2, payload.count - 1, 1] {
            let truncated = String(payload.prefix(keep))
            #expect(throws: RoundInvite.InviteError.self) {
                try RoundInvite.decode(payload: truncated, now: Date(timeIntervalSince1970: 1_800_000_000))
            }
        }
    }

    @Test("a corrupted payload is rejected")
    func rejectsCorruptPayload() {
        for junk in ["", "not-base64!!", "////", "e30"] {
            #expect(throws: RoundInvite.InviteError.self) {
                try RoundInvite.decode(payload: junk, now: Date(timeIntervalSince1970: 1_800_000_000))
            }
        }
    }

    @Test("an invite whose deadline has passed is rejected as expired, not silently accepted")
    func rejectsExpiredInvite() throws {
        let invite = Self.invite()
        let after = invite.sealDeadline.addingTimeInterval(1)
        do {
            _ = try RoundInvite.decode(payload: try invite.encodedPayload(), now: after)
            Issue.record("an expired invite decoded")
        } catch let error as RoundInvite.InviteError {
            #expect(error == .expired(sealDeadline: invite.sealDeadline))
        }
    }

    @Test("a payload from a newer app version is refused by number, not mis-parsed")
    func rejectsUnknownVersion() throws {
        let payload = try Self.invite().encodedPayload()
        let data = try #require(RoundInvite.base64URLDecode(payload))
        let decoded = try JSONSerialization.jsonObject(with: data)
        var object = try #require(decoded as? [String: Any])
        object["v"] = RoundInvite.version + 1
        let bumped = RoundInvite.base64URLEncode(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        do {
            _ = try RoundInvite.decode(payload: bumped, now: Date(timeIntervalSince1970: 1_800_000_000))
            Issue.record("a future-version invite decoded")
        } catch let error as RoundInvite.InviteError {
            #expect(error == .unsupportedVersion(RoundInvite.version + 1))
        }
    }

    @Test("a malformed contract address, relay, round id or sides list is rejected")
    func rejectsMalformedFields() throws {
        let payload = try Self.invite().encodedPayload()
        let baseData = try #require(RoundInvite.base64URLDecode(payload))
        let baseObject = try JSONSerialization.jsonObject(with: baseData)
        let base = try #require(baseObject as? [String: Any])

        let mutations: [(String, Any)] = [
            ("contract", String(repeating: "ab", count: 31)),   // too short
            ("contract", String(repeating: "zz", count: 32)),   // not hex
            ("relay", "ftp://relay.test"),                      // wrong scheme
            ("relay", "not a url at all"),
            ("round", "not-a-uuid"),
            ("question", "   "),                                // blank
            ("crew", ""),
            ("sides", ["Yes"]),                                 // must be exactly two
            ("sides", ["Yes", "No", "Maybe"]),
            ("sides", ["Yes", " "])
        ]
        for (key, value) in mutations {
            var object = base
            object[key] = value
            let mutated = RoundInvite.base64URLEncode(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            #expect(throws: RoundInvite.InviteError.self, "\(key) = \(value) should be rejected") {
                try RoundInvite.decode(payload: mutated, now: Date(timeIntervalSince1970: 1_800_000_000))
            }
        }
    }

    @Test("a slip:// URL with the wrong host or scheme is rejected")
    func rejectsForeignURLs() throws {
        let payload = try Self.invite().encodedPayload()
        for string in ["slip://seal/\(payload)", "https://join/\(payload)", "slip://join"] {
            let url = try #require(URL(string: string))
            #expect(throws: RoundInvite.InviteError.self) {
                try RoundInvite.decode(url: url, now: Date(timeIntervalSince1970: 1_800_000_000))
            }
        }
    }

    /// The privacy invariant, enforced on the one payload that is designed to be shared.
    @Test("the payload carries no witness, secret or credential material")
    func payloadCarriesNoPrivateMaterial() throws {
        let payload = try Self.invite().encodedPayload()
        let payloadData = try #require(RoundInvite.base64URLDecode(payload))
        let json = String(decoding: payloadData, as: UTF8.self)

        for forbidden in ["salt", "choice", "secret", "witness", "token", "bearer", "pick", "commitment", "proof"] {
            #expect(!json.lowercased().contains(forbidden), "invite payload must not mention \(forbidden)")
        }
        // The field set itself is the guarantee: exactly these keys, nothing more.
        let parsed = try JSONSerialization.jsonObject(with: payloadData)
        let object = try #require(parsed as? [String: Any])
        #expect(Set(object.keys) == ["v", "relay", "contract", "round", "question", "sides", "crew", "palette", "deadline"])
    }
}
