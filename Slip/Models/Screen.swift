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
        sampleQuestion = question
        sideLabels = sides
        if let firstSide = sides.first {
            selectedSide = firstSide
        }
        hasLocalSeal = false
        return round
    }

    /// Accepts completion only for the current local identity, preventing a proof from
    /// an abandoned round being relabelled as the newly edited slip.
    @discardableResult
    func markLocalSeal(roundID: UUID) -> Bool {
        guard localRound.id == roundID else { return false }
        hasLocalSeal = true
        return true
    }

    func isCurrentLocalRound(_ roundID: UUID) -> Bool {
        localRound.id == roundID
    }

    static func preview(_ screen: SlipScreen) -> AppModel {
        let model = AppModel()
        model.isPreview = true
        model.screen = screen
        return model
    }
}
