import Testing
@testable import Slip

struct SealAccessibilityTests {
    @Test("Hold to seal exposes its label and a cancellable pending confirmation")
    func holdLabelAndPendingAction() {
        let ready = SealHoldAccessibility(isPending: false)
        let pending = SealHoldAccessibility(isPending: true)
        #expect(ready.label == "Hold to seal")
        #expect(pending.label == ready.label)
        #expect(ready.value == "Ready to seal")
        #expect(pending.value == "Confirmation in progress")
        #expect(ready.sealActionName == "Seal your pick")
        #expect(ready.cancelActionName == "Cancel sealing")
        #expect(pending.sealActionName == ready.sealActionName)
        #expect(pending.cancelActionName == ready.cancelActionName)
        #expect(ready.hint.contains("1.2 seconds"))
        #expect(pending.hint.contains("cancel"))
    }

    @Test("The shared ticket and already-sealed control exposes no choice until peek activation")
    func sealedPickLabelAndPrivacy() throws {
        var peek = PickPeekState()
        let concealed = SealedPickAccessibility(isVisible: peek.isVisible, choice: "Synthetic private side")
        #expect(concealed.label == "Your sealed pick")
        #expect(concealed.value == "Your pick is concealed")
        #expect(concealed.peekActionName == "Peek at your pick")
        #expect(concealed.concealActionName == "Conceal your pick")
        #expect(!concealed.hint.isEmpty)
        #expect(![concealed.label, concealed.value, concealed.hint,
                  concealed.peekActionName, concealed.concealActionName]
            .contains(where: { $0.contains("Synthetic private side") }))

        let activation = peek.activate()
        _ = try #require(activation)
        let visible = SealedPickAccessibility(isVisible: peek.isVisible, choice: "Synthetic private side")
        #expect(visible.value == "Your pick: Synthetic private side")
        #expect(visible.peekActionName == concealed.peekActionName)
        #expect(visible.concealActionName == concealed.concealActionName)
        let concealActivation = peek.activate()
        #expect(concealActivation == nil)
        #expect(!peek.isVisible)
    }

    @Test("Repeated named Peek preserves its timer and cancelled expiry cannot hide a later peek")
    func stalePeekExpiry() throws {
        var peek = PickPeekState()
        let firstActivation = peek.show()
        let first = try #require(firstActivation)
        let repeatedShow = peek.show()
        #expect(repeatedShow == nil)
        #expect(peek.isVisible)
        peek.expire(first)
        #expect(!peek.isVisible)

        let staleActivation = peek.show()
        let stale = try #require(staleActivation)
        peek.conceal()
        let secondActivation = peek.show()
        let second = try #require(secondActivation)
        peek.expire(stale)
        #expect(peek.isVisible)
        peek.expire(second)
        #expect(!peek.isVisible)

        let thirdActivation = peek.show()
        let third = try #require(thirdActivation)
        peek.touch(pressing: true)
        peek.expire(third)
        #expect(peek.isVisible)
        peek.touch(pressing: false)
        #expect(!peek.isVisible)
    }

    @Test("Repeated concealment is harmless and departure invalidates pending expiry and touch visibility")
    func departureConceals() throws {
        var peek = PickPeekState()
        let activation = peek.activate()
        let pending = try #require(activation)
        peek.conceal()
        peek.conceal()
        peek.expire(pending)
        #expect(!peek.isVisible)
        peek.touch(pressing: true)
        peek.conceal()
        #expect(!peek.isVisible)
    }
}
