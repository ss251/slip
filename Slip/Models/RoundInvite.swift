import Foundation
import MidnightKit

/// What one phone must hand another so both seal into the *same* round.
///
/// Today each install derives its round locally, so two phones that "join the same slip"
/// actually create two unrelated rounds. An invite carries the round's identity — where to
/// submit, which contract, which round, and the human context needed to render it — so the
/// joiner enrols into the creator's round instead of starting its own.
///
/// **This payload is public.** It travels through whatever channel the crew already uses,
/// so it carries no witness material: no choice, no salt, no device secret, and no relay
/// credential. Only the commitment and the proof ever travel, and neither is in here.
/// `RoundInviteTests.payloadCarriesNoPrivateMaterial` holds that line.
struct RoundInvite: Equatable, Sendable {
    /// Where the joiner submits. The relay authorises use, not picks.
    let relayURL: URL
    /// The crew's deployed contract, 64 lowercase hex characters.
    let contractAddressHex: String
    /// Identifies the round across devices; the creator's `LocalRound.id`.
    let roundID: UUID
    let question: String
    /// Contract encoding: index 0 is choice `1`, index 1 is choice `0`.
    let sides: [String]
    let crewName: String
    /// Keeps the crew's generated art identical on every member's screen.
    let paletteKey: String
    let sealDeadline: Date

    enum InviteError: Error, Equatable {
        case malformed
        case unsupportedVersion(Int)
        case expired(sealDeadline: Date)
    }

    /// Bumped whenever the field set changes; an older app refuses a newer invite by number
    /// rather than by mis-parsing it.
    static let version = 1
    static let scheme = "slip"
    static let joinHost = "join"
}

// MARK: - Encoding

extension RoundInvite {
    /// A deterministic, URL-safe payload. Stable across runs and processes: the field order
    /// is sorted, the date is whole seconds, and nothing derives from a per-process seed.
    func encodedPayload() throws -> String {
        let wire = Wire(
            v: Self.version,
            relay: relayURL.absoluteString,
            contract: contractAddressHex.lowercased(),
            round: roundID.uuidString.lowercased(),
            question: question,
            sides: sides,
            crew: crewName,
            palette: paletteKey,
            deadline: Int(sealDeadline.timeIntervalSince1970.rounded())
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return Self.base64URLEncode(try encoder.encode(wire))
    }

    /// `slip://join/<payload>` — the link a member sends. A web fallback needs a real
    /// domain the owner controls, so it is deliberately not invented here.
    func inviteURL() throws -> URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.joinHost
        components.path = "/" + (try encodedPayload())
        guard let url = components.url else { throw InviteError.malformed }
        return url
    }
}

// MARK: - Decoding

extension RoundInvite {
    /// Rejects anything that is not a complete, current, still-open invite. `now` is
    /// injected so the expiry rule is testable without sleeping.
    static func decode(payload: String, now: Date = Date()) throws -> RoundInvite {
        guard let data = base64URLDecode(payload) else { throw InviteError.malformed }
        let wire: Wire
        do { wire = try JSONDecoder().decode(Wire.self, from: data) } catch { throw InviteError.malformed }

        guard wire.v == version else { throw InviteError.unsupportedVersion(wire.v) }
        guard let relay = URL(string: wire.relay), relay.scheme == "https" || relay.scheme == "http",
              relay.host?.isEmpty == false else { throw InviteError.malformed }
        let contract = wire.contract.lowercased()
        guard contract.count == 64, Data(hex: contract) != nil else { throw InviteError.malformed }
        guard let round = UUID(uuidString: wire.round) else { throw InviteError.malformed }
        guard !wire.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw InviteError.malformed }
        guard wire.sides.count == 2, wire.sides.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw InviteError.malformed }
        guard !wire.crew.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw InviteError.malformed }

        let deadline = Date(timeIntervalSince1970: TimeInterval(wire.deadline))
        guard deadline > now else { throw InviteError.expired(sealDeadline: deadline) }

        return RoundInvite(relayURL: relay, contractAddressHex: contract, roundID: round,
                           question: wire.question, sides: wire.sides, crewName: wire.crew,
                           paletteKey: wire.palette, sealDeadline: deadline)
    }

    /// Accepts the `slip://join/<payload>` form as well as a bare payload, because people
    /// paste both.
    static func decode(url: URL, now: Date = Date()) throws -> RoundInvite {
        guard url.scheme == scheme, url.host == joinHost else { throw InviteError.malformed }
        let payload = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        return try decode(payload: payload, now: now)
    }
}

// MARK: - Wire form and base64url

extension RoundInvite {
    /// Short keys keep the link scannable as a QR code. Order is fixed by `.sortedKeys`.
    fileprivate struct Wire: Codable {
        let v: Int
        let relay: String
        let contract: String
        let round: String
        let question: String
        let sides: [String]
        let crew: String
        let palette: String
        let deadline: Int
    }

    /// RFC 4648 §5 without padding: safe in a URL path and in a QR alphanumeric run.
    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ string: String) -> Data? {
        guard !string.isEmpty else { return nil }
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s.append(String(repeating: "=", count: (4 - s.count % 4) % 4))
        return Data(base64Encoded: s)
    }
}
