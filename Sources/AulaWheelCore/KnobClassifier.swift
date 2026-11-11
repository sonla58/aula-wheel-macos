import Foundation

public struct KnobKeyEvent: Equatable, Sendable {
    public var input: KnobInput
    public var isDown: Bool
    public var isRepeat: Bool
    public var modifiers: ModifierSet
    /// Seconds on the same clock the caller passes to `tick(now:)`.
    public var time: TimeInterval

    public init(_ input: KnobInput, isDown: Bool, isRepeat: Bool = false, modifiers: ModifierSet = [], time: TimeInterval) {
        self.input = input
        self.isDown = isDown
        self.isRepeat = isRepeat
        self.modifiers = modifiers
        self.time = time
    }
}

public enum ClassifiedEvent: Equatable, Sendable {
    /// A knob detent or knob press, reported at its key-down time.
    case knob(KnobInput, ModifierSet, time: TimeInterval)
    /// An F10/F11/F12 press (or autorepeat) that must keep its system Mute/Volume meaning.
    case functionKey(KnobInput, ModifierSet)
}

/// Tells knob events from F-row presses that share the same key codes.
///
/// The firmware emits knob events as a down/up pair a few milliseconds apart, while a finger
/// keeps a key down for much longer. A key still down after `maxHold` is a real key press.
/// Bluetooth sometimes delays a key-up mid-spin, so right after other knob events the limit
/// is raised to `burstMaxHold`: nobody presses F11/F12 while turning the knob.
public final class KnobClassifier {
    public var maxHold: TimeInterval
    public var burstMaxHold: TimeInterval
    public var burstWindow: TimeInterval
    /// How long past `maxHold` to wait for a key-up that is probably already in flight
    /// (the key reads as released but its key-up event has not been handled yet).
    public var inFlightGrace: TimeInterval = 0.060
    static let recheckInterval: TimeInterval = 0.010

    private struct Pending {
        var time: TimeInterval
        var modifiers: ModifierSet
        var limit: TimeInterval
        var checkAt: TimeInterval
    }

    private var pending: [KnobInput: Pending] = [:]
    private var held: Set<KnobInput> = []
    private var lastKnobTime: TimeInterval?

    public init(maxHold: TimeInterval, burstMaxHold: TimeInterval? = nil, burstWindow: TimeInterval = 0) {
        self.maxHold = maxHold
        self.burstMaxHold = max(burstMaxHold ?? maxHold, maxHold)
        self.burstWindow = burstWindow
    }

    private func limit(at time: TimeInterval) -> TimeInterval {
        if let lastKnobTime, time - lastKnobTime <= burstWindow { return burstMaxHold }
        return maxHold
    }

    public var nextDeadline: TimeInterval? {
        pending.values.map(\.checkAt).min()
    }

    public func handle(_ event: KnobKeyEvent) -> [ClassifiedEvent] {
        let input = event.input
        if event.isDown {
            if event.isRepeat {
                let wasPending = pending.removeValue(forKey: input) != nil
                let wasHeld = !held.insert(input).inserted
                // A held Mute key must not toggle mute on every autorepeat.
                if input == .press && wasHeld && !wasPending { return [] }
                return [.functionKey(input, event.modifiers)]
            }
            held.remove(input)
            let limit = limit(at: event.time)
            pending[input] = Pending(
                time: event.time, modifiers: event.modifiers, limit: limit, checkAt: event.time + limit)
            return []
        }

        if held.remove(input) != nil { return [] }
        guard let down = pending.removeValue(forKey: input) else { return [] }
        if event.time - down.time <= down.limit {
            lastKnobTime = event.time
            return [.knob(input, down.modifiers, time: down.time)]
        }
        return [.functionKey(input, down.modifiers)]
    }

    /// - Parameter isKeyDown: whether the key is still physically down, if the caller can tell.
    public func tick(now: TimeInterval, isKeyDown: (KnobInput) -> Bool = { _ in true }) -> [ClassifiedEvent] {
        var out: [ClassifiedEvent] = []
        for input in KnobInput.allCases {
            guard var down = pending[input], now >= down.checkAt, now - down.time > down.limit else { continue }
            if !isKeyDown(input) && now - down.time <= down.limit + inFlightGrace {
                down.checkAt = now + Self.recheckInterval
                pending[input] = down
                continue
            }
            pending.removeValue(forKey: input)
            held.insert(input)
            out.append(.functionKey(input, down.modifiers))
        }
        return out
    }

    public func reset() {
        pending.removeAll()
        held.removeAll()
        lastKnobTime = nil
    }
}
