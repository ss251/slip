import Foundation
import Testing
@testable import Slip

@Suite(.serialized)
@MainActor
struct AppModelCoverageTests {
    @Test("leaving a tab clears its navigation history and back falls home")
    func emptyHistoryAndNotices() {
        let model = AppModel()
        model.go(.crewDetail)
        model.tab(.you)
        model.back()

        #expect(model.screen == .home)
        #expect(model.history.isEmpty)
        model.inform("Synthetic local operation failed")
        #expect(model.notice == "Synthetic local operation failed")
        model.inform("Synthetic retry complete")
        #expect(model.notice == "Synthetic retry complete")
    }

    @Test("replacing the draft rejects the old round and preserves an empty draft safely")
    func currentIdentityTracksReplacement() {
        let model = AppModel()
        let original = model.localRound
        #expect(model.isCurrentLocalRound(original.id))
        #expect(model.markLocalSeal(roundID: original.id))
        let originalSelection = model.selectedSide

        let replacement = model.startLocalRound(
            question: "Unfinished synthetic draft?", sides: [], crewName: "Local sample",
            createdAt: Date(timeIntervalSince1970: 1_788_600_000)
        )

        #expect(!model.isCurrentLocalRound(original.id))
        #expect(model.isCurrentLocalRound(replacement.id))
        #expect(!model.hasLocalSeal)
        #expect(!model.markLocalSeal(roundID: original.id))
        #expect(model.sideLabels.isEmpty)
        let selectionWasNotInvented = model.selectedSide == originalSelection
        #expect(selectionWasNotInvented)
    }

    @Test("preview routes retain their stable identifiers without navigation history")
    func previewIdentity() {
        for screen in SlipScreen.allCases {
            let preview = AppModel.preview(screen)
            #expect(screen.id == screen.rawValue)
            #expect(preview.isPreview)
            #expect(preview.screen == screen)
            #expect(preview.history.isEmpty)
            #expect(!preview.hasLocalSeal)
        }
    }
}
