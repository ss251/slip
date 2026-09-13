import Foundation
import MidnightKit

/// What one phone must hand another so both seal into the *same* round.
///
/// Today each install derives its round locally, so two phones that "join the same slip"
/// actually create two unrelated rounds. An invite carries the round's identity — where to
/// submit, which contract, which round, and the human context needed to render it — so the
/// joiner adopts local presentation metadata. It does not enrol a member on chain.
///
/// **This payload is public.** It travels through whatever channel the crew already uses,
/// so it carries no witness material: no choice, no salt, no device secret, and no relay
/// credential. Only the commitment and the proof ever travel, and neither is in here.
/// Tests constrain the wire schema; callers must still supply only public text and URLs.
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
    /// Bound untrusted input before base64 allocation and JSON decoding on the main actor.
    static let maximumPayloadBytes = 16_384

    private static func isPublicRelayURL(_ url: URL) -> Bool {
        (url.scheme == "https" || url.scheme == "http") && url.host?.isEmpty == false
            && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }
}

// MARK: - Encoding

extension RoundInvite {
    /// A deterministic, URL-safe payload. Stable across runs and processes: the field order
    /// is sorted, the date is whole seconds, and nothing derives from a per-process seed.
    func encodedPayload() throws -> String {
        guard Self.isPublicRelayURL(relayURL),
              let deadline = Int(exactly: sealDeadline.timeIntervalSince1970.rounded())
        else { throw InviteError.malformed }
        let wire = Wire(
            v: Self.version,
            relay: relayURL.absoluteString,
            contract: contractAddressHex.lowercased(),
            round: roundID.uuidString.lowercased(),
            question: question,
            sides: sides,
            crew: crewName,
            palette: paletteKey,
            deadline: deadline
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = Self.base64URLEncode(try encoder.encode(wire))
        guard payload.utf8.count <= Self.maximumPayloadBytes else { throw InviteError.malformed }
        return payload
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
        guard payload.utf8.count <= maximumPayloadBytes,
              payload.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
                  || (48...57).contains($0) || $0 == 45 || $0 == 95 }),
              let data = base64URLDecode(payload) else { throw InviteError.malformed }
        let wire: Wire
        do { wire = try JSONDecoder().decode(Wire.self, from: data) } catch { throw InviteError.malformed }

        guard wire.v == version else { throw InviteError.unsupportedVersion(wire.v) }
        guard let relay = URL(string: wire.relay), isPublicRelayURL(relay) else { throw InviteError.malformed }
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

    /// Accepts only `slip://join/<payload>`; bare payloads use the separate overload.
    static func decode(url: URL, now: Date = Date()) throws -> RoundInvite {
        guard url.scheme == scheme, url.host == joinHost,
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { throw InviteError.malformed }
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
