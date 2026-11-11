import Foundation
import Testing
@testable import AulaWheelCore

@Suite struct ScrollingTests {
    @Test func directionsUseWheelSigns() {
        var planner = ScrollPlanner(config: ScrollConfig())
        #expect(planner.delta(direction: .down, scale: 1, speed: .medium, time: 0) == (0, -100))
        #expect(planner.delta(direction: .up, scale: 0.25, speed: .slow, time: 10) == (0, 10))
        #expect(planner.delta(direction: .right, scale: 1, speed: .fast, time: 20) == (-250, 0))
        #expect(planner.delta(direction: .left, scale: 1, speed: .fast, time: 30) == (250, 0))
    }

    @Test func invertFlipsSign() {
        var config = ScrollConfig()
        config.invert = true
        var planner = ScrollPlanner(config: config)
        #expect(planner.delta(direction: .down, scale: 1, speed: .medium, time: 0) == (0, 100))
    }

    @Test func fastDetentsAccelerateOnlyInSameDirection() {
        var planner = ScrollPlanner(config: ScrollConfig())
        #expect(planner.delta(direction: .down, scale: 1, speed: .medium, time: 0).dy == -100)
        #expect(planner.delta(direction: .down, scale: 1, speed: .medium, time: 0.045).dy == -200)
        #expect(planner.delta(direction: .down, scale: 1, speed: .medium, time: 0.075).dy == -300)
        #expect(planner.delta(direction: .down, scale: 1, speed: .medium, time: 0.085).dy == -300)
        #expect(planner.delta(direction: .up, scale: 1, speed: .medium, time: 0.095).dy == 100)
        #expect(planner.delta(direction: .up, scale: 1, speed: .medium, time: 0.200).dy == 100)
    }

    @Test func animatorEmitsWholeDistanceThenIdles() {
        var animator = ScrollAnimator(duration: 0.120)
        animator.add(dx: 0, dy: -100)
        animator.add(dx: 37, dy: 0)
        var totalX: Int32 = 0
        var totalY: Int32 = 0
        var frames = 0
        while !animator.isIdle && frames < 1000 {
            let step = animator.step(dt: 1.0 / 120)
            totalX += step.dx
            totalY += step.dy
            frames += 1
        }
        #expect(totalY == -100)
        #expect(totalX == 37)
        #expect(frames < 40)
    }

    @Test func zeroDurationFlushesImmediately() {
        var animator = ScrollAnimator(duration: 0)
        animator.add(dx: 0, dy: 42)
        #expect(animator.step(dt: 0.008) == (0, 42))
        #expect(animator.isIdle)
    }
}
