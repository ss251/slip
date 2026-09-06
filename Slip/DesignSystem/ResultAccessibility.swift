import SwiftUI

enum ResultAccessibility {
    static func roster(name: String, detail: String? = nil, value: String? = nil,
                       valueDetail: String? = nil, score: String? = nil, sealed: Bool? = nil) -> String {
        var parts = [name]
        if let sealed {
            // A counterparty's private choice is never part of a sealed row's label.
            parts.append(sealed ? "Sealed" : "Waiting")
            if let detail { parts.append(detail) }
        } else {
            if let detail { parts.append(detail) }
            if let value { parts.append(value == "—" ? "No opened pick" : value) }
            if let valueDetail { parts.append(valueDetail) }
        }
        if let score {
            if let points = Int(score) {
                parts.append("\(points) \(abs(points) == 1 ? "point" : "points")")
            } else if score == "—" {
                parts.append("No score")
            } else {
                parts.append(score)
            }
        }
        return parts.joined(separator: ". ")
    }

    static func verdict(side: String, picks: Int, calledIt: Bool = false) -> String {
        var parts = [side, "\(picks) \(picks == 1 ? "pick" : "picks")"]
        if calledIt { parts.append("called it") }
        return parts.joined(separator: ". ")
    }
}

#if DEBUG
enum ResultPreviewAction: CaseIterable {
    case opening, everyoneOpened, callSheet, standings

    var title: String {
        switch self {
        case .opening: "Preview opening"
        case .everyoneOpened: "Preview everyone opened"
        case .callSheet: "Preview call sheet"
        case .standings: "Preview standings"
        }
    }

    var destination: SlipScreen {
        switch self {
        case .opening: .opening
        case .everyoneOpened: .awaiting
        case .callSheet: .settle
        case .standings: .standings
        }
    }
}

/// The preview's existing context-menu destinations also support a single activation.
struct ResultPreviewAccessibility: ViewModifier {
    @Environment(AppModel.self) private var model
    let action: ResultPreviewAction

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("\(action.title) locally. No shared round is changed.")
            .accessibilityAction { model.go(action.destination) }
            .accessibilityAction(named: Text(action.title)) { model.go(action.destination) }
    }
}
#endif
