import SwiftUI
import Testing
@testable import Slip

@MainActor
struct HeadingAccessibilityTests {
    @Test("Screen headers expose the title as a heading without absorbing the subtitle")
    func screenHeaderLabel() {
        let header = ScreenHeader(title: "No result.", subtitle: "SATURDAY CREW · VOIDED")
        expectHeading(header.headingAccessibility, label: "No result.")
    }

    @Test("Sheet headings retain the title without announcing the decorative seal")
    func sheetHeadingLabel() {
        let heading = SheetHeading(title: "Sealed on this iPhone", light: true, sealIndicator: true)
        expectHeading(heading.headingAccessibility, label: "Sealed on this iPhone")
    }

    @Test("Form headings name the form independently of the cancel control")
    func formHeadingLabel() {
        let heading = FormHeading(title: "New slip", cancel: {})
        expectHeading(heading.headingAccessibility, label: "New slip")
    }

    @Test("Guide step one reads its title and explanation without the decorative pick")
    func privatePickStepLabel() {
        #expect(HowStepContent.steps[0].accessibilityLabel ==
                "Step 1. Pick in private. You choose on your own iPhone. The pick never uploads.")
    }

    @Test("Guide step two reads the seal explanation after its step number and title")
    func sealStepLabel() {
        #expect(HowStepContent.steps[1].accessibilityLabel ==
                "Step 2. Seal it. Your phone proves the pick without showing it. Only the proof leaves.")
    }

    @Test("Guide step three reads the privacy rule without the decorative roster count")
    func waitingStepLabel() {
        #expect(HowStepContent.steps[2].accessibilityLabel ==
                "Step 3. Wait together. Everyone sees who has sealed, never what. Nudge the stragglers.")
    }

    @Test("Guide step four reads the opening explanation without decorative Yes and No examples")
    func openingStepLabel() {
        #expect(HowStepContent.steps[3].accessibilityLabel ==
                "Step 4. Open together. At the deadline every pick opens at once, each checked against its seal.")
    }

    @Test("Guide step five reads the scoring explanation without a detached plus-one stop")
    func scoringStepLabel() {
        #expect(HowStepContent.steps[4].accessibilityLabel ==
                "Step 5. Keep score. The steward calls what happened. Winners take a point, losers take the banter.")
    }

    private func expectHeading(_ semantics: HeadingAccessibility, label: String) {
        #expect(semantics.label == label)
        #expect(semantics.traits.contains(.isHeader))
        #expect(!semantics.traits.contains(.isButton))
    }
}
