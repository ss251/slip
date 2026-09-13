import Foundation
import SwiftUI

enum SlipScreen: String, CaseIterable, Identifiable, Sendable {
    case howItWorks = "00-how-slip-works"
    case home = "01-home"
    case firstRun = "01b-home-first-run"
    case newSlip = "02-new-slip"
    case invite = "02b-invite"
    case seal = "03-seal-your-pick"
    case sealing = "03b-sealing"
    case ticket = "04-sealed-ticket"
    case room = "05-sealed-room"
    case opening = "06a-opening"
    case verdict = "06b-verdict"
    case standings = "07-standings"
    case crews = "08-crews"
    case crewDetail = "08b-crew-detail"
    case you = "09-you"
    case settle = "10-settle"
    case awaiting = "10b-awaiting-the-call"
    case challenge = "10c-challenge"
    case voided = "10d-voided"
    case proofFailed = "11a-proof-failed"
    case postingLater = "11b-sealed-posting-later"
    case alreadySealed = "11c-already-sealed"
    case satOut = "11d-verdict-sat-out"
    case mismatch = "11e-reveal-mismatch"

    var id: String { rawValue }
    var hasTabs: Bool { [.home, .firstRun, .crews, .you].contains(self) }
}

enum PreviewContent {
    static let question = "Will it rain on Saturday?"
    static let crew = "Saturday crew"
    static let members = ["You", "Ana", "Raj", "Maya", "Tomás"]
    static let names = ["Ana", "You", "Raj", "Maya", "Tomás"]
    static let scores = [12, 10, 7, 6, 4]
    static func initial(_ name: String) -> String { name == "You" ? "S" : String(name.prefix(1)) }
}

@MainActor @Observable
final class AppModel {
    var isPreview = false
    var screen: SlipScreen = .home
    var history: [SlipScreen] = []
    var notice: String?
    var selectedSide = "Yes"
    var sideLabels = ["Yes", "No"]
    var sampleQuestion = PreviewContent.question
    private(set) var localRound = LocalRound(
        question: PreviewContent.question,
        sides: ["Yes", "No"],
        crewName: PreviewContent.crew
    )
    private(set) var hasLocalSeal = false
    /// Changes even when a replacement invite reuses its public UUID.
    private(set) var localRoundRevision = UUID()

    /// Public network identity captured for the imported round, independent of mutable defaults.
    private struct JoinedNetwork: Equatable {
        let relayURL: URL
        let contractAddressHex: String
    }
    private var joinedNetwork: JoinedNetwork?

    func go(_ destination: SlipScreen) {
        history.append(screen)
        screen = destination
    }

    func back() { screen = history.popLast() ?? .home }
    func tab(_ destination: SlipScreen) { history.removeAll(); screen = destination }
    func inform(_ message: String) { notice = message }

    /// Freezes editable creation fields into a new local identity. Starting another
    /// round invalidates only the app's public completion flag; sealed private display
    /// facts remain owned by `SealFlowModel` for this process session.
    @discardableResult
    func startLocalRound(
        question: String,
        sides: [String],
        crewName: String,
        createdAt: Date = Date(),
        sealDeadline: Date? = nil
    ) -> LocalRound {
        let round = LocalRound(
            question: question,
            sides: sides,
            crewName: crewName,
            createdAt: createdAt,
            sealDeadline: sealDeadline
        )
        localRound = round
        localRoundRevision = UUID()
        joinedNetwork = nil
        sampleQuestion = question
        sideLabels = sides
        if let firstSide = sides.first {
            selectedSide = firstSide
        }
        hasLocalSeal = false
        return round
    }

    /// Accepts completion only for the current UUID. Callers must also invalidate old
    /// work when an invite replaces metadata while retaining that UUID.
    @discardableResult
    func markLocalSeal(roundID: UUID) -> Bool {
        guard localRound.id == roundID else { return false }
        hasLocalSeal = true
        return true
    }

    func isCurrentLocalRound(_ roundID: UUID) -> Bool {
        localRound.id == roundID
    }

    /// What accepting an invite did, so the UI can be honest about it.
    enum JoinOutcome: Equatable {
        /// Imported metadata and saved the invite's relay/contract for a later launch.
        /// This does not reconfigure the running sealing service.
        case joinedAndAdoptedNetwork
        /// Joined the round, but saved setup is incomplete or points to a *different*
        /// relay or contract, so its network setup was left alone. The running flow
        /// is not reconfigured by import; this does not establish connected readiness.
        case joinedWithNetworkConflict(configuredContractHex: String)
        /// Imported metadata; saved network setup already matched.
        case joined
    }

    /// Imports public round metadata. An identical rejoin preserves its local seal;
    /// changing any bound metadata or network identity replaces the local round.
    /// `beforeReplacingRound` synchronously invalidates cached presentation and in-flight
    /// work before a caller renders a replacement, including one reusing the same UUID.
    ///
    /// Network setup is adopted only when it is absent or already identical. An invite
    /// arrives from outside the app, so it must not be able to silently repoint a
    /// configured device at another relay or contract.
    @discardableResult
    func join(
        invite: RoundInvite,
        defaults: UserDefaults = .standard,
        beforeReplacingRound: (UUID) -> Void = { _ in }
    ) -> JoinOutcome {
        let existing = NetworkSetup.load(defaults: defaults)
        let incomingNetwork = JoinedNetwork(relayURL: invite.relayURL,
                                            contractAddressHex: invite.contractAddressHex.lowercased())
        let configuredNetwork = existing.map {
            JoinedNetwork(relayURL: $0.relayURL, contractAddressHex: $0.contractAddressHex.lowercased())
        }
        // Both the round's original network and the current configuration must agree.
        // A defaults edit must not relabel an old seal as a new contract's seal.
        let isRejoin = localRound.id == invite.roundID
            && joinedNetwork == incomingNetwork
            && configuredNetwork == incomingNetwork
            && localRound.question == invite.question
            && localRound.sides == invite.sides
            && localRound.crewName == invite.crewName
            && localRound.sealDeadline == invite.sealDeadline
        if !isRejoin {
            beforeReplacingRound(localRound.id)
            localRoundRevision = UUID()
            joinedNetwork = incomingNetwork
            localRound = LocalRound(
                id: invite.roundID,
                question: invite.question,
                sides: invite.sides,
                crewName: invite.crewName,
                sealDeadline: invite.sealDeadline
            )
            hasLocalSeal = false
        }
        sampleQuestion = localRound.question
        sideLabels = localRound.sides
        if !isRejoin, let firstSide = invite.sides.first { selectedSide = firstSide }
        history.removeAll()
        screen = .seal

        switch existing {
        case .none where [NetworkSetup.relayKey, NetworkSetup.contractKey, NetworkSetup.tokenKey]
            .contains(where: { defaults.object(forKey: $0) != nil }):
            // Invalid/partial settings are still configured state, not permission for
            // an external link to overwrite the endpoint or erase its bearer token.
            return .joinedWithNetworkConflict(
                configuredContractHex: defaults.string(forKey: NetworkSetup.contractKey) ?? "")
        case .none:
            NetworkSetup(relayURL: invite.relayURL,
                         contractAddressHex: invite.contractAddressHex).save(defaults: defaults)
            return .joinedAndAdoptedNetwork
        case .some(let setup) where setup.contractAddressHex.lowercased() == invite.contractAddressHex.lowercased()
            && setup.relayURL == invite.relayURL:
            return .joined
        case .some(let setup):
            return .joinedWithNetworkConflict(configuredContractHex: setup.contractAddressHex)
        }
    }

    static func preview(_ screen: SlipScreen) -> AppModel {
        let model = AppModel()
        model.isPreview = true
        model.screen = screen
        return model
    }
}
