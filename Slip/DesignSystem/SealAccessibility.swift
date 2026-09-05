import SwiftUI

/// Shared spoken copy for the safety-timed confirmation; it never contains a pick.
struct SealHoldAccessibility {
    let isPending: Bool
    let label = "Hold to seal"
    let sealActionName = "Seal your pick"
    let cancelActionName = "Cancel sealing"
    var value: String { isPending ? "Confirmation in progress" : "Ready to seal" }
    var hint: String {
        isPending ? "Activate again to cancel before the 1.2-second confirmation finishes."
            : "Confirms your pick after 1.2 seconds. Activate again to cancel."
    }
}

/// Concealed semantics do not interpolate the private choice into any spoken field.
struct SealedPickAccessibility {
    let isVisible: Bool
    let choice: String
    let label = "Your sealed pick"
    let peekActionName = "Peek at your pick"
    let concealActionName = "Conceal your pick"
    var value: String { isVisible ? "Your pick: \(choice)" : "Your pick is concealed" }
    var hint: String {
        isVisible ? "Activate to conceal your pick. It also conceals automatically."
            : "Activate to peek briefly. Activate again to conceal."
    }
}

/// Gesture and accessibility activation share visibility, without storing the pick.
/// A cancelled timer cannot conceal a newer peek or a subsequent touch-and-hold.
struct PickPeekState {
    private(set) var isVisible = false
    private var expiryID: UUID?

    mutating func activate() -> UUID? {
        guard !isVisible else { conceal(); return nil }
        return show()
    }

    /// Repeating the named Peek action does not hide the pick or restart its timer.
    mutating func show() -> UUID? {
        guard !isVisible else { return nil }
        isVisible = true
        let id = UUID()
        expiryID = id
        return id
    }

    mutating func touch(pressing: Bool) {
        expiryID = nil
        isVisible = pressing
    }

    mutating func expire(_ id: UUID) {
        guard expiryID == id else { return }
        conceal()
    }

    mutating func conceal() {
        expiryID = nil
        isVisible = false
    }
}

/// One actionable accessibility element replaces the private pick's visual children.
/// Unsealed cards retain their ordinary reading order and expose no peek action.
struct SealedPickAccessibilityModifier: ViewModifier {
    let enabled: Bool
    let semantics: SealedPickAccessibility
    var activate: () -> Void
    var show: () -> Void
    var conceal: () -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(semantics.label)
                .accessibilityValue(semantics.value)
                .accessibilityHint(semantics.hint)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { activate() }
                // Stable action names avoid SwiftUI retaining a stale action title
                // while the separately updated value and hint describe another state.
                .accessibilityAction(named: Text(semantics.peekActionName)) { show() }
                .accessibilityAction(named: Text(semantics.concealActionName)) { conceal() }
        } else {
            content
        }
    }
}
