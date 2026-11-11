import Foundation
import Testing
@testable import AulaWheelCore

@Suite struct KnobClassifierTests {
    let classifier = KnobClassifier(maxHold: 0.040)

    @Test func shortPressIsKnob() {
        #expect(classifier.handle(KnobKeyEvent(.rotateCW, isDown: true, modifiers: .shift, time: 1.000)) == [])
        #expect(classifier.nextDeadline == 1.040)
        #expect(classifier.handle(KnobKeyEvent(.rotateCW, isDown: false, time: 1.015))
            == [.knob(.rotateCW, .shift, time: 1.000)])
        #expect(classifier.nextDeadline == nil)
    }

    @Test func holdBeyondThresholdBecomesFunctionKeyOnTick() {
        _ = classifier.handle(KnobKeyEvent(.press, isDown: true, modifiers: .option, time: 2.000))
        #expect(classifier.tick(now: 2.030) == [])
        #expect(classifier.tick(now: 2.041) == [.functionKey(.press, .option)])
        #expect(classifier.handle(KnobKeyEvent(.press, isDown: false, time: 2.090)) == [])
    }

    @Test func lateKeyUpWithoutTickIsFunctionKey() {
        _ = classifier.handle(KnobKeyEvent(.rotateCCW, isDown: true, time: 3.000))
        #expect(classifier.handle(KnobKeyEvent(.rotateCCW, isDown: false, time: 3.090)) == [.functionKey(.rotateCCW, [])])
    }

    @Test func autorepeatIsFunctionKey() {
        _ = classifier.handle(KnobKeyEvent(.rotateCW, isDown: true, time: 4.000))
        #expect(classifier.handle(KnobKeyEvent(.rotateCW, isDown: true, isRepeat: true, time: 4.030))
            == [.functionKey(.rotateCW, [])])
        #expect(classifier.handle(KnobKeyEvent(.rotateCW, isDown: true, isRepeat: true, time: 4.100))
            == [.functionKey(.rotateCW, [])])
        #expect(classifier.handle(KnobKeyEvent(.rotateCW, isDown: false, time: 4.200)) == [])
        #expect(classifier.nextDeadline == nil)
    }

    @Test func fastDetentsStayKnob() {
        var out: [ClassifiedEvent] = []
        for i in 0..<5 {
            let t = 5.0 + Double(i) * 0.030
            out += classifier.handle(KnobKeyEvent(.rotateCW, isDown: true, time: t))
            out += classifier.handle(KnobKeyEvent(.rotateCW, isDown: false, time: t + 0.015))
        }
        #expect(out.count == 5)
        #expect(out.allSatisfy { if case .knob = $0 { true } else { false } })
    }

    @Test func heldMuteKeyDoesNotRepeat() {
        _ = classifier.handle(KnobKeyEvent(.press, isDown: true, time: 1.0))
        #expect(classifier.tick(now: 1.05) == [.functionKey(.press, [])])
        #expect(classifier.handle(KnobKeyEvent(.press, isDown: true, isRepeat: true, time: 1.5)) == [])
        #expect(classifier.handle(KnobKeyEvent(.press, isDown: true, isRepeat: true, time: 1.6)) == [])
        #expect(classifier.handle(KnobKeyEvent(.press, isDown: false, time: 1.7)) == [])
    }

    @Test func muteRepeatBeforeTickFiresOnce() {
        _ = classifier.handle(KnobKeyEvent(.press, isDown: true, time: 1.0))
        #expect(classifier.handle(KnobKeyEvent(.press, isDown: true, isRepeat: true, time: 1.5)) == [.functionKey(.press, [])])
        #expect(classifier.handle(KnobKeyEvent(.press, isDown: true, isRepeat: true, time: 1.6)) == [])
    }

    @Test func releasedKeyWaitsForInFlightKeyUp() {
        _ = classifier.handle(KnobKeyEvent(.rotateCW, isDown: true, time: 1.000))
        #expect(classifier.tick(now: 1.050, isKeyDown: { _ in false }) == [])
        #expect(classifier.nextDeadline == 1.060)
        #expect(classifier.handle(KnobKeyEvent(.rotateCW, isDown: false, time: 1.015))
            == [.knob(.rotateCW, [], time: 1.000)])
        #expect(classifier.nextDeadline == nil)
    }

    @Test func missingKeyUpFallsBackToFunctionKeyAfterGrace() {
        _ = classifier.handle(KnobKeyEvent(.rotateCCW, isDown: true, time: 1.000))
        #expect(classifier.tick(now: 1.090, isKeyDown: { _ in false }) == [])
        #expect(classifier.tick(now: 1.101, isKeyDown: { _ in false }) == [.functionKey(.rotateCCW, [])])
    }

    @Test func slowKeyUpMidSpinStaysKnob() {
        let c = KnobClassifier(maxHold: 0.060, burstMaxHold: 0.150, burstWindow: 0.300)
        _ = c.handle(KnobKeyEvent(.rotateCW, isDown: true, time: 1.000))
        _ = c.handle(KnobKeyEvent(.rotateCW, isDown: false, time: 1.015))
        _ = c.handle(KnobKeyEvent(.rotateCW, isDown: true, time: 1.030))
        #expect(c.nextDeadline == 1.180)
        #expect(c.tick(now: 1.120) == [])
        #expect(c.handle(KnobKeyEvent(.rotateCW, isDown: false, time: 1.130)) == [.knob(.rotateCW, [], time: 1.030)])
    }

    @Test func isolatedLongHoldIsFunctionKey() {
        let c = KnobClassifier(maxHold: 0.060, burstMaxHold: 0.150, burstWindow: 0.300)
        _ = c.handle(KnobKeyEvent(.rotateCW, isDown: true, time: 1.000))
        _ = c.handle(KnobKeyEvent(.rotateCW, isDown: false, time: 1.015))
        _ = c.handle(KnobKeyEvent(.rotateCW, isDown: true, time: 1.400))
        #expect(c.tick(now: 1.461) == [.functionKey(.rotateCW, [])])
    }

    @Test func burstRequiresARealKnobEvent() {
        let c = KnobClassifier(maxHold: 0.060, burstMaxHold: 0.150, burstWindow: 0.300)
        _ = c.handle(KnobKeyEvent(.rotateCW, isDown: true, time: 1.000))
        _ = c.handle(KnobKeyEvent(.rotateCW, isDown: false, time: 1.090))
        _ = c.handle(KnobKeyEvent(.rotateCW, isDown: true, time: 1.200))
        #expect(c.handle(KnobKeyEvent(.rotateCW, isDown: false, time: 1.290)) == [.functionKey(.rotateCW, [])])
    }

    @Test func strayKeyUpIsIgnored() {
        #expect(classifier.handle(KnobKeyEvent(.press, isDown: false, time: 6.0)) == [])
    }
}

@Suite struct GestureRecognizerTests {
    let recognizer = GestureRecognizer(doublePressWindow: 0.250)

    @Test func rotationIsImmediate() {
        #expect(recognizer.handle(.rotateCCW, modifiers: .shift, time: 1)
            == [.rotate(clockwise: false, modifiers: .shift, time: 1)])
    }

    @Test func singlePressWaitsForWindow() {
        #expect(recognizer.handle(.press, modifiers: .command, time: 1.0) == [])
        #expect(recognizer.nextDeadline == 1.25)
        #expect(recognizer.tick(now: 1.2) == [])
        #expect(recognizer.tick(now: 1.26) == [.press(.command)])
        #expect(recognizer.nextDeadline == nil)
    }

    @Test func secondPressInsideWindowIsDoublePress() {
        _ = recognizer.handle(.press, modifiers: [], time: 1.0)
        #expect(recognizer.handle(.press, modifiers: [], time: 1.16) == [.doublePress([])])
        #expect(recognizer.tick(now: 2) == [])
    }

    @Test func rotationFlushesPendingPress() {
        _ = recognizer.handle(.press, modifiers: [], time: 1.0)
        #expect(recognizer.handle(.rotateCW, modifiers: [], time: 1.1)
            == [.press([]), .rotate(clockwise: true, modifiers: [], time: 1.1)])
    }

    @Test func pressesAreImmediateWhenDoublePressDisabled() {
        recognizer.doublePressEnabled = false
        #expect(recognizer.handle(.press, modifiers: [], time: 1.0) == [.press([])])
        #expect(recognizer.nextDeadline == nil)
    }
}
