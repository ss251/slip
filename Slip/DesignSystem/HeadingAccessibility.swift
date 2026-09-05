import SwiftUI

/// Shared title semantics keep headings distinct from nearby context and controls.
struct HeadingAccessibility: Sendable {
    let label: String
    let traits: AccessibilityTraits = .isHeader
}
