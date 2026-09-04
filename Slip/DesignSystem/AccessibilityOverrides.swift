import SwiftUI

/// Debug renders may exercise the same fallbacks as the system settings without
/// trying to mutate SwiftUI's read-only accessibility environment values.
struct AccessibilityOverrides: Sendable {
    var reduceMotion = false
    var reduceTransparency = false
    var increaseContrast = false
}

private struct AccessibilityOverridesKey: EnvironmentKey {
    static let defaultValue = AccessibilityOverrides()
}

extension EnvironmentValues {
    var slipAccessibility: AccessibilityOverrides {
        get { self[AccessibilityOverridesKey.self] }
        set { self[AccessibilityOverridesKey.self] = newValue }
    }
}
