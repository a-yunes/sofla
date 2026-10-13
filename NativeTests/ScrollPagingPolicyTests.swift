import Testing

@testable import AppLauncher

@Suite
struct ScrollPagingPolicyTests {
    @Test
    func discreteWheelNotchPagesOnceAndUsesShortCooldown() {
        var policy = ScrollPagingPolicy()

        #expect(
            policy.pageDelta(
                scrollingDelta: -1, phase: .discrete, hasMomentum: false, timestamp: 1
            ) == 1)
        #expect(
            policy.pageDelta(
                scrollingDelta: -1, phase: .discrete, hasMomentum: false, timestamp: 1.1
            ) == nil)
        #expect(
            policy.pageDelta(
                scrollingDelta: 1, phase: .discrete, hasMomentum: false, timestamp: 1.2
            ) == -1)
    }

    @Test
    func modestTrackpadSwipePagesOnlyOncePerGesture() {
        var policy = ScrollPagingPolicy(threshold: 12)

        #expect(
            policy.pageDelta(
                scrollingDelta: -3, phase: .began, hasMomentum: false, timestamp: 1
            ) == nil)
        #expect(
            policy.pageDelta(
                scrollingDelta: -9, phase: .changed, hasMomentum: false, timestamp: 1.02
            ) == 1)
        #expect(
            policy.pageDelta(
                scrollingDelta: -30, phase: .changed, hasMomentum: false, timestamp: 1.04
            ) == nil)
        #expect(
            policy.pageDelta(
                scrollingDelta: -5, phase: .ended, hasMomentum: false, timestamp: 1.06
            ) == nil)
    }

    @Test
    func slowAndFastThresholdsChangeOnlyTrackpadSensitivity() {
        var slow = ScrollPagingPolicy(threshold: 18)
        #expect(
            slow.pageDelta(
                scrollingDelta: -12, phase: .began, hasMomentum: false, timestamp: 1
            ) == nil)
        #expect(
            slow.pageDelta(
                scrollingDelta: -6, phase: .changed, hasMomentum: false, timestamp: 1.01
            ) == 1)

        var fast = ScrollPagingPolicy(threshold: 7)
        #expect(
            fast.pageDelta(
                scrollingDelta: 7, phase: .began, hasMomentum: false, timestamp: 2
            ) == -1)
    }

    @Test
    func changingThresholdResetsAnInProgressGesture() {
        var policy = ScrollPagingPolicy(threshold: 18)
        #expect(
            policy.pageDelta(
                scrollingDelta: -10, phase: .began, hasMomentum: false, timestamp: 1
            ) == nil)

        policy.updateThreshold(7)

        #expect(
            policy.pageDelta(
                scrollingDelta: -1, phase: .changed, hasMomentum: false, timestamp: 1.01
            ) == nil)
        #expect(
            policy.pageDelta(
                scrollingDelta: -6, phase: .changed, hasMomentum: false, timestamp: 1.02
            ) == 1)
    }

    @Test
    func momentumAndCancelledGesturesDoNotPage() {
        var policy = ScrollPagingPolicy()

        #expect(
            policy.pageDelta(
                scrollingDelta: -100, phase: .changed, hasMomentum: true, timestamp: 1
            ) == nil)
        #expect(
            policy.pageDelta(
                scrollingDelta: -8, phase: .began, hasMomentum: false, timestamp: 2
            ) == nil)
        #expect(
            policy.pageDelta(
                scrollingDelta: -8, phase: .cancelled, hasMomentum: false, timestamp: 2.1
            ) == nil)
        #expect(
            policy.pageDelta(
                scrollingDelta: -5, phase: .changed, hasMomentum: false, timestamp: 2.2
            ) == nil)
    }
}
