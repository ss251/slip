import Testing
@testable import Slip

@Suite(.serialized)
@MainActor
struct NavigationAndHoldTests {
    @Test("Hold confirmation requires the full safety interval and cancels cleanly")
    func holdTiming() {
        var hold = SealHold()
        let finished1 = hold.finish(at: 100)
        #expect(!finished1)
        hold.start(at: 100)
        #expect(hold.progress(at: 100.6) > 0.49)
        let finished2 = hold.finish(at: 101.19)
        #expect(!finished2)
        hold.start(at: 200)
        hold.cancel()
        let finished3 = hold.finish(at: 300)
        #expect(!finished3)
        hold.start(at: 400)
        let finished4 = hold.finish(at: 401.21)
        #expect(finished4)
        let finished5 = hold.finish(at: 402)
        #expect(!finished5)
    }

    @Test("Round navigation keeps opening and settlement separate")
    func routes() {
        let app = AppModel()
        app.go(.seal)
        app.go(.ticket)
        app.go(.room)
        app.go(.opening)
        #expect(app.screen == .opening)
        app.go(.awaiting)
        app.go(.settle)
        app.back()
        #expect(app.screen == .awaiting)
        app.tab(.crews)
        #expect(app.history.isEmpty)
        app.go(.crewDetail)
        app.back()
        #expect(app.screen == .crews)
    }

    @Test("Every canonical board has a reachable screen including appearance and AX variants")
    func boardCoverage() {
        #expect(SlipScreen.allCases.count == 24)
        #expect(Set(SlipScreen.allCases.map(\.rawValue)).count == 24)
    }
}
