import Testing
@testable import Slip

@Suite(.serialized)
struct RevealMotionTests {
    @Test("Reveal rows stagger by 60 milliseconds and cap at five")
    func staggerPlan() {
        #expect(RevealMotionPlan.maximumStaggeredRows == 5)
        #expect(RevealMotionPlan.delay(forRowAt: 0) == .zero)
        #expect(RevealMotionPlan.delay(forRowAt: 1) == SlipMotion.revealStagger)

        let fifthDelay = SlipMotion.revealStagger * 4
        #expect(RevealMotionPlan.delay(forRowAt: 4) == fifthDelay)
        #expect(RevealMotionPlan.delay(forRowAt: 5) == fifthDelay)
        #expect(RevealMotionPlan.delay(forRowAt: 20) == fifthDelay)
    }

    @Test("Reduce Motion replaces the concealed flip with a crossfade state")
    func visualStates() {
        let flipping = RevealMotionPlan.visualState(isRevealed: false, reduceMotion: false)
        #expect(flipping.opacity == RevealMotionPlan.hiddenOpacity)
        #expect(flipping.rotationDegrees == RevealMotionPlan.hiddenAngle)

        let crossfading = RevealMotionPlan.visualState(isRevealed: false, reduceMotion: true)
        #expect(crossfading.opacity == RevealMotionPlan.hiddenOpacity)
        #expect(crossfading.rotationDegrees == RevealMotionPlan.restingAngle)

        let revealed = RevealMotionPlan.visualState(isRevealed: true, reduceMotion: false)
        #expect(revealed.opacity == SlipOpacity.opaque)
        #expect(revealed.rotationDegrees == RevealMotionPlan.restingAngle)
    }

    @Test("Cancelling a partial reveal leaves no result row concealed")
    func cancellationCompletesParticipatingRows() {
        let completed = RevealMotionPlan.completedRows(
            afterCancelling: [0, 1],
            participatingIndices: [0, 1, 2, 4]
        )

        #expect(completed == [0, 1, 2, 4])
    }
}
