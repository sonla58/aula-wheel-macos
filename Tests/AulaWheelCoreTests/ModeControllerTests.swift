import Foundation
import Testing
@testable import AulaWheelCore

@Suite struct ModeControllerTests {
    let modes = AppConfig.defaultModes

    func controller(mode: String? = "volume") -> ModeController {
        ModeController(modes: modes, currentModeID: mode, scrollSpeed: .medium, pickerAutoSelect: 1.5)
    }

    @Test func unknownSavedModeFallsBackToFirst() {
        #expect(controller(mode: "gone").currentMode.id == "volume")
    }

    @Test func rotationRunsModeActionWithModifiers() {
        let c = controller()
        #expect(c.handle(.rotate(clockwise: true, modifiers: [], time: 1), now: 1) == [.perform(.volumeUp(fine: false), time: 1)])
        #expect(c.handle(.rotate(clockwise: false, modifiers: .option, time: 2), now: 2) == [.perform(.volumeDown(fine: true), time: 2)])
        #expect(c.handle(.press([]), now: 3) == [.perform(.mute, time: 3)])
    }

    @Test func pressInScrollModeCyclesSpeed() {
        let c = controller(mode: "scroll")
        #expect(c.handle(.press([]), now: 1) == [.stateChanged, .showScrollSpeed(.fast)])
        #expect(c.scrollSpeed == .fast)
    }

    @Test func pickerOpensMovesWrapsAndSelects() {
        let c = controller()
        #expect(c.handle(.doublePress([]), now: 1) == [.showPicker(modes: modes, highlighted: 0)])
        #expect(c.isPickerOpen)
        #expect(c.handle(.rotate(clockwise: false, modifiers: [], time: 1.1), now: 1.1) == [.showPicker(modes: modes, highlighted: 2)])
        #expect(c.handle(.rotate(clockwise: true, modifiers: [], time: 1.2), now: 1.2) == [.showPicker(modes: modes, highlighted: 0)])
        #expect(c.handle(.rotate(clockwise: true, modifiers: [], time: 1.3), now: 1.3) == [.showPicker(modes: modes, highlighted: 1)])
        #expect(c.handle(.press([]), now: 1.4) == [.closePicker, .stateChanged, .showMode(modes[1])])
        #expect(c.currentMode.id == "scroll")
        #expect(!c.isPickerOpen)
    }

    @Test func pickerAutoSelectsAfterIdle() {
        let c = controller()
        _ = c.handle(.doublePress([]), now: 1)
        _ = c.handle(.rotate(clockwise: true, modifiers: [], time: 1.5), now: 1.5)
        #expect(c.nextDeadline == 3.0)
        #expect(c.tick(now: 2.9) == [])
        #expect(c.tick(now: 3.0) == [.closePicker, .stateChanged, .showMode(modes[1])])
        #expect(c.nextDeadline == nil)
    }

    @Test func vendorPingWithoutKnobUseIsIgnored() {
        let c = controller()
        #expect(c.vendorPing() == [])
        #expect(!c.firmwareInRGB)
    }

    @Test func vendorPingShowsRGBOnceThenKnobUseReturns() {
        let c = controller(mode: "scroll")
        _ = c.handle(.rotate(clockwise: true, modifiers: [], time: 4), now: 4)
        #expect(c.vendorPing() == [.showRGB])
        #expect(c.vendorPing() == [])
        #expect(c.firmwareInRGB)
        #expect(c.handle(.rotate(clockwise: true, modifiers: [], time: 5), now: 5)
            == [.showMode(modes[1]), .perform(.scroll(direction: .down, scale: 1), time: 5)])
        #expect(!c.firmwareInRGB)
        #expect(c.vendorPing() == [.showRGB])
    }

    @Test func vendorPingBeforeAnyKnobUseIsIgnoredEvenAfterHold() {
        let c = controller(mode: "scroll")
        _ = c.handle(.rotate(clockwise: true, modifiers: [], time: 1), now: 1)
        _ = c.vendorPing()
        _ = c.vendorPing()
        #expect(c.firmwareInRGB)
    }

    @Test func vendorPingClosesPicker() {
        let c = controller()
        _ = c.handle(.doublePress([]), now: 1)
        #expect(c.vendorPing() == [.closePicker, .showRGB])
        #expect(!c.isPickerOpen)
    }

    @Test func selectModeFromMenu() {
        let c = controller()
        #expect(c.selectMode(id: "media") == [.stateChanged, .showMode(modes[2])])
        #expect(c.selectMode(id: "nope") == [])
        #expect(c.currentMode.id == "media")
    }

    @Test func replaceModesKeepsCurrentWhenPresent() {
        let c = controller(mode: "media")
        c.replaceModes(Array(modes.reversed()))
        #expect(c.currentMode.id == "media")
        c.replaceModes([modes[0]])
        #expect(c.currentMode.id == "volume")
    }
}

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
