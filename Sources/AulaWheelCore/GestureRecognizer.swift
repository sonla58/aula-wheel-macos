import Foundation

public enum KnobGesture: Equatable, Sendable {
    case rotate(clockwise: Bool, modifiers: ModifierSet, time: TimeInterval)
    case press(ModifierSet)
    case doublePress(ModifierSet)
}

/// Turns knob events into rotations, single presses and double presses.
///
/// A single press is only reported once `doublePressWindow` has passed without a second press.
public final class GestureRecognizer {
    public var doublePressWindow: TimeInterval
    /// When false, presses are reported immediately (used while the mode picker is open).
    public var doublePressEnabled = true

    private var pendingPress: (time: TimeInterval, modifiers: ModifierSet)?

    public init(doublePressWindow: TimeInterval) {
        self.doublePressWindow = doublePressWindow
    }

    public var nextDeadline: TimeInterval? {
        pendingPress.map { $0.time + doublePressWindow }
    }

    public func handle(_ input: KnobInput, modifiers: ModifierSet, time: TimeInterval) -> [KnobGesture] {
        switch input {
        case .rotateCW, .rotateCCW:
            var out = flushPendingPress()
            out.append(.rotate(clockwise: input == .rotateCW, modifiers: modifiers, time: time))
            return out
        case .press:
            if let first = pendingPress {
                pendingPress = nil
                if time - first.time <= doublePressWindow {
                    return [.doublePress(first.modifiers)]
                }
                pendingPress = (time, modifiers)
                return [.press(first.modifiers)]
            }
            if !doublePressEnabled { return [.press(modifiers)] }
            pendingPress = (time, modifiers)
            return []
        }
    }

    public func tick(now: TimeInterval) -> [KnobGesture] {
        guard let first = pendingPress, now - first.time > doublePressWindow else { return [] }
        return flushPendingPress()
    }

    public func reset() {
        pendingPress = nil
    }

    private func flushPendingPress() -> [KnobGesture] {
        guard let first = pendingPress else { return [] }
        pendingPress = nil
        return [.press(first.modifiers)]
    }
}
