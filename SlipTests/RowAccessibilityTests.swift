import Testing
@testable import Slip

@MainActor
struct RowAccessibilityTests {
    @Test("Home feed rows speak the question before crew, status and metadata")
    func homeCompactRow() {
        #expect(RowAccessibility.slip(
            question: "Does the demo survive the all-hands?",
            crew: "Office pool",
            status: RowAccessibility.sealStatus(sealed: true),
            metadata: "Opens 17:00"
        ) == "Does the demo survive the all-hands?, Office pool, Sealed, Opens 17:00")
    }

    @Test("The Home hero summary excludes its separately reachable CTA")
    func homeHero() {
        #expect(RowAccessibility.slip(
            question: "Will it rain on Saturday?",
            crew: "Saturday crew",
            status: "Ana, Raj and 1 more sealed",
            metadata: "Seal by Fri 20:00"
        ) == "Will it rain on Saturday?, Saturday crew, Ana, Raj and 1 more sealed, Seal by Fri 20:00")
    }

    @Test("Seal context speaks the question first without manufacturing a status")
    func contextRow() {
        #expect(RowAccessibility.slip(
            question: "Will it rain on Saturday?",
            crew: "Saturday crew",
            metadata: "local proof only"
        ) == "Will it rain on Saturday?, Saturday crew, local proof only")
    }

    @Test("Crew member rows keep identity, detail and visible value together")
    func memberRow() {
        #expect(RowAccessibility.member(name: "Ana", detail: "Steward", value: "12") == "Ana, Steward, 12")
    }

    @Test("Both sealed and waiting member summaries suppress a hidden pick value")
    func protectedMemberValue() {
        #expect(RowAccessibility.member(name: "Ana", value: "Hidden choice", sealed: true) == "Ana, Sealed")
        #expect(RowAccessibility.member(name: "Maya", value: "Hidden choice", sealed: false) == "Maya, Waiting")
    }

    @Test("Inline seal status contains no decorative glyph label")
    func statusTag() {
        #expect(RowAccessibility.sealStatus(sealed: true) == "Sealed")
        #expect(RowAccessibility.sealStatus(sealed: false) == "Waiting")
    }

    @Test("Profile history speaks question, crew, score meaning and metadata")
    func profileHistory() {
        #expect(RowAccessibility.slip(
            question: "Will Raj actually ship this week?",
            crew: "Saturday crew",
            status: RowAccessibility.points("+1"),
            metadata: "No · called it"
        ) == "Will Raj actually ship this week?, Saturday crew, +1 point, No · called it")
    }

    @Test("Crew-detail open slips speak the question before Waiting")
    func crewOpenSlip() {
        #expect(RowAccessibility.slip(
            question: "Will it rain on Saturday?",
            crew: "Saturday crew",
            status: RowAccessibility.sealStatus(sealed: false),
            metadata: "Seal by Fri 20:00 · 3 of 5 sealed"
        ) == "Will it rain on Saturday?, Saturday crew, Waiting, Seal by Fri 20:00 · 3 of 5 sealed")
    }

    @Test("Each profile statistic speaks its value with its unit")
    func profileStatistic() {
        #expect(RowAccessibility.statistic(value: "18", label: "called") == "18 called")
        #expect(RowAccessibility.statistic(value: "64%", label: "hit rate") == "64% hit rate")
    }

    @Test("Invite slip summaries retain waiting state and seal deadline")
    func inviteSlip() {
        #expect(RowAccessibility.slip(
            question: "Will it rain on Saturday?",
            crew: "Saturday crew",
            status: RowAccessibility.sealStatus(sealed: false),
            metadata: "Seal by Fri 20:00 · 3 of 5 sealed"
        ) == "Will it rain on Saturday?, Saturday crew, Waiting, Seal by Fri 20:00 · 3 of 5 sealed")
    }

    @Test("Invite members are named once, independently of decorative avatars")
    func inviteMembers() {
        #expect(RowAccessibility.invitationMembers(names: ["Ana", "Raj", "Maya"], additionalCount: 1) == "Ana, Raj, Maya, and 1 more")
        #expect(RowAccessibility.invitationMembers(names: ["Ana"], additionalCount: 0) == "Ana")
    }

    @Test("New-slip crew picker includes the same members at every text size")
    func newSlipCrewPicker() {
        #expect(RowAccessibility.crewPicker(crew: "Saturday crew", members: ["Ana", "Raj", "Maya"]) == "Saturday crew, Ana, Raj, Maya")
    }

    @Test("Scores distinguish singular points and unavailable scores")
    func scoreUnits() {
        #expect(RowAccessibility.points("+1") == "+1 point")
        #expect(RowAccessibility.points("0") == "0 points")
        #expect(RowAccessibility.points("12") == "12 points")
        #expect(RowAccessibility.points("—") == "No score")
    }
}
