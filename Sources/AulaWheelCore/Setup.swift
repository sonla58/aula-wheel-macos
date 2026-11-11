import Foundation

public enum SetupStep: Int, CaseIterable, Sendable {
    case welcome, permissions, keyboard, tryIt
}

public struct SetupStatus: Equatable, Sendable {
    public var accessibility: Bool
    public var inputMonitoring: Bool
    public var keyboardConnected: Bool

    public init(accessibility: Bool, inputMonitoring: Bool, keyboardConnected: Bool = false) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.keyboardConnected = keyboardConnected
    }

    public var permissionsGranted: Bool { accessibility && inputMonitoring }
}

public enum SetupFlow {
    /// Where the setup window opens at launch, or nil when it should stay closed.
    public static func launchStep(completed: Bool, status: SetupStatus) -> SetupStep? {
        if completed {
            return status.permissionsGranted ? nil : .permissions
        }
        if status.permissionsGranted { return .keyboard }
        if status.accessibility || status.inputMonitoring { return .permissions }
        return .welcome
    }

    public static func canContinue(from step: SetupStep, status: SetupStatus) -> Bool {
        switch step {
        case .permissions: status.permissionsGranted
        case .keyboard: status.keyboardConnected
        case .welcome, .tryIt: true
        }
    }

    /// The app does nothing without both permissions, but a keyboard can be connected later.
    public static func canSkip(_ step: SetupStep) -> Bool {
        step == .keyboard
    }
}

public enum KnobExercise: CaseIterable, Sendable {
    case rotate, press, openPicker, pickMode
}

/// Tracks which knob gestures the user has tried during setup.
public struct KnobPractice: Equatable, Sendable {
    public private(set) var done: Set<KnobExercise> = []

    public init() {}

    public var isComplete: Bool { done.count == KnobExercise.allCases.count }

    public mutating func record(_ gesture: KnobGesture) {
        switch gesture {
        case .rotate: done.insert(.rotate)
        case .press: done.insert(.press)
        case .doublePress: break
        }
    }

    public mutating func record(_ effects: [ModeEffect]) {
        var closedPicker = false
        for effect in effects {
            switch effect {
            case .showPicker: done.insert(.openPicker)
            case .closePicker: closedPicker = true
            case .showMode where closedPicker: done.insert(.pickMode)
            default: break
            }
        }
    }
}
