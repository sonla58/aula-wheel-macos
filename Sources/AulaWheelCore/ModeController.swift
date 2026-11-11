import Foundation

public enum ModeEffect: Equatable, Sendable {
    case perform(Action, time: TimeInterval)
    case showMode(ModeConfig)
    case showScrollSpeed(ScrollSpeed)
    case showRGB
    case showPicker(modes: [ModeConfig], highlighted: Int)
    case closePicker
    /// The current mode or scroll speed changed and should be persisted.
    case stateChanged
}

/// Owns the current app mode, scroll speed, mode picker and firmware RGB tracking.
public final class ModeController {
    public private(set) var modes: [ModeConfig]
    public private(set) var currentIndex: Int
    public private(set) var scrollSpeed: ScrollSpeed
    public private(set) var pickerHighlight: Int?
    /// True after the keyboard reported a vendor ping, i.e. the firmware knob is driving the LEDs.
    public private(set) var firmwareInRGB = false
    public var pickerAutoSelect: TimeInterval

    private var pickerLastInteraction: TimeInterval = 0
    private var knobUsedSincePing = false

    public init(modes: [ModeConfig], currentModeID: String?, scrollSpeed: ScrollSpeed, pickerAutoSelect: TimeInterval) {
        precondition(!modes.isEmpty)
        self.modes = modes
        self.currentIndex = modes.firstIndex { $0.id == currentModeID } ?? 0
        self.scrollSpeed = scrollSpeed
        self.pickerAutoSelect = pickerAutoSelect
    }

    public var currentMode: ModeConfig { modes[currentIndex] }
    public var isPickerOpen: Bool { pickerHighlight != nil }

    public var nextDeadline: TimeInterval? {
        isPickerOpen ? pickerLastInteraction + pickerAutoSelect : nil
    }

    public func handle(_ gesture: KnobGesture, now: TimeInterval) -> [ModeEffect] {
        var effects: [ModeEffect] = []
        knobUsedSincePing = true
        if firmwareInRGB {
            firmwareInRGB = false
            effects.append(.showMode(currentMode))
        }

        if let highlight = pickerHighlight {
            pickerLastInteraction = now
            switch gesture {
            case .rotate(let clockwise, _, _):
                let next = (highlight + (clockwise ? 1 : -1) + modes.count) % modes.count
                pickerHighlight = next
                effects.append(.showPicker(modes: modes, highlighted: next))
            case .press, .doublePress:
                effects += select(highlight)
            }
            return effects
        }

        switch gesture {
        case .doublePress:
            pickerHighlight = currentIndex
            pickerLastInteraction = now
            effects.append(.showPicker(modes: modes, highlighted: currentIndex))
        case .press(let modifiers):
            effects += run(currentMode.action(for: .press, modifiers: modifiers), time: now)
        case .rotate(let clockwise, let modifiers, let time):
            let input: KnobInput = clockwise ? .rotateCW : .rotateCCW
            effects += run(currentMode.action(for: input, modifiers: modifiers), time: time)
        }
        return effects
    }

    public func tick(now: TimeInterval) -> [ModeEffect] {
        guard let highlight = pickerHighlight, now - pickerLastInteraction >= pickerAutoSelect else { return [] }
        return select(highlight)
    }

    /// Called for every vendor report from the keyboard. Only the first one after knob use counts,
    /// since the firmware also sends it while already in RGB and when switching back.
    public func vendorPing() -> [ModeEffect] {
        guard !firmwareInRGB, knobUsedSincePing else { return [] }
        firmwareInRGB = true
        knobUsedSincePing = false
        var effects: [ModeEffect] = []
        if isPickerOpen {
            pickerHighlight = nil
            effects.append(.closePicker)
        }
        effects.append(.showRGB)
        return effects
    }

    public func selectMode(id: String) -> [ModeEffect] {
        guard let index = modes.firstIndex(where: { $0.id == id }) else { return [] }
        var effects: [ModeEffect] = []
        if isPickerOpen {
            pickerHighlight = nil
            effects.append(.closePicker)
        }
        currentIndex = index
        return effects + [.stateChanged, .showMode(currentMode)]
    }

    public func setScrollSpeed(_ speed: ScrollSpeed) -> [ModeEffect] {
        scrollSpeed = speed
        return [.stateChanged, .showScrollSpeed(speed)]
    }

    public func replaceModes(_ newModes: [ModeConfig]) {
        precondition(!newModes.isEmpty)
        let currentID = currentMode.id
        modes = newModes
        currentIndex = newModes.firstIndex { $0.id == currentID } ?? 0
        pickerHighlight = nil
    }

    private func select(_ index: Int) -> [ModeEffect] {
        pickerHighlight = nil
        currentIndex = index
        return [.closePicker, .stateChanged, .showMode(currentMode)]
    }

    private func run(_ action: Action, time: TimeInterval) -> [ModeEffect] {
        switch action {
        case .none:
            return []
        case .cycleScrollSpeed:
            return setScrollSpeed(scrollSpeed.next)
        default:
            return [.perform(action, time: time)]
        }
    }
}
