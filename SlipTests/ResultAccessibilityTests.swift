import Testing
@testable import Slip

struct ResultAccessibilityTests {
    @Test("Result rows preserve complete privacy context at every text size")
    func rosterLabels() {
        #expect(ResultAccessibility.roster(name: "You", value: "Yes", valueDetail: "only you can see this")
                == "You. Yes. only you can see this")
        #expect(ResultAccessibility.roster(name: "Raj", detail: "Hasn’t opened · 1h 40m left", value: "PRIVATE PICK", sealed: true)
                == "Raj. Sealed. Hasn’t opened · 1h 40m left")
        #expect(ResultAccessibility.roster(name: "Maya", value: "PRIVATE PICK", sealed: false) == "Maya. Waiting")
        #expect(ResultAccessibility.roster(name: "Ana", value: "Yes", score: "+1") == "Ana. Yes. 1 point")
        #expect(ResultAccessibility.roster(name: "Raj", value: "No", score: "0") == "Raj. No. 0 points")
        #expect(ResultAccessibility.roster(name: "Tomás", detail: "Sat this one out", value: "—", score: "—")
                == "Tomás. Sat this one out. No opened pick. No score")
    }

    @Test("Each verdict side has one complete spoken summary, including sat-out counts")
    func verdictLabels() {
        #expect(ResultAccessibility.verdict(side: "Yes", picks: 3, calledIt: true) == "Yes. 3 picks. called it")
        #expect(ResultAccessibility.verdict(side: "No", picks: 2) == "No. 2 picks")
        #expect(ResultAccessibility.verdict(side: "No", picks: 1, satOut: 1) == "No. 1 pick. 1 sat out")
    }

    @Test("Accessible preview actions name and navigate to the existing context-menu destinations")
    @MainActor func previewActions() {
        let expectations: [(ResultPreviewAction, String, SlipScreen)] = [
            (.opening, "Preview opening", .opening),
            (.everyoneOpened, "Preview everyone opened", .awaiting),
            (.callSheet, "Preview call sheet", .settle),
            (.standings, "Preview standings", .standings)
        ]
        for (action, title, destination) in expectations {
            #expect(action.title == title)
            let model = AppModel.preview(.room)
            model.go(action.destination)
            #expect(model.screen == destination)
            #expect(model.history == [.room])
        }
    }
}
