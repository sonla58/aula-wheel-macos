import AppKit
import AulaWheelCore

/// NX_KEYTYPE_* codes for system-defined (media) key events.
enum SystemKey: Int {
    case soundUp = 0
    case soundDown = 1
    case mute = 7
    case play = 16
    case next = 17
    case previous = 18
}

final class EventPoster {
    private let source = CGEventSource(stateID: .privateState)

    func postSystemKey(_ key: SystemKey, modifiers: ModifierSet) {
        for down in [true, false] {
            // 0xA / 0xB in bits 8-15 mark key down / key up for NX_SUBTYPE_AUX_CONTROL_BUTTONS (8).
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(modifiers.eventFlags) | UInt(state << 8)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (key.rawValue << 16) | (state << 8),
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    func postKey(code: UInt16, modifiers: ModifierSet, repeatCount: Int) {
        let flags = CGEventFlags(rawValue: modifiers.eventFlags)
        for _ in 0..<max(repeatCount, 1) {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
                event.flags = flags
                event.post(tap: .cghidEventTap)
            }
        }
    }

    func postScroll(dx: Int32, dy: Int32) {
        guard dx != 0 || dy != 0,
              let event = CGEvent(
                  scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        else { return }
        if let location = CGEvent(source: nil)?.location { event.location = location }
        event.flags = []
        event.post(tap: .cghidEventTap)
    }
}
