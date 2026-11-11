import Foundation

/// A physical knob input after it has been told apart from the F-row keys.
public enum KnobInput: String, Codable, CaseIterable, Sendable {
    case rotateCW, rotateCCW, press
}

public enum InputSource: String, Codable, Sendable {
    /// The keyboard sends Consumer Volume/Mute; the app remaps them on that device only
    /// and tells the knob apart from F10-F12 by press duration.
    case consumerRemap
    /// The knob has already been remapped on the keyboard to three dedicated key codes.
    case functionKeys
}

public enum ScrollSpeed: String, Codable, CaseIterable, Sendable {
    case slow, medium, fast

    public var next: ScrollSpeed {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

public struct KnobKeyCodes: Codable, Equatable, Sendable {
    public var rotateCW: UInt16
    public var rotateCCW: UInt16
    public var press: UInt16

    public init(rotateCW: UInt16, rotateCCW: UInt16, press: UInt16) {
        self.rotateCW = rotateCW
        self.rotateCCW = rotateCCW
        self.press = press
    }

    // kVK_F18 / kVK_F19 / kVK_F20: what `ConsumerRemap` turns Vol+ / Vol- / Mute into.
    public static let remapped = KnobKeyCodes(rotateCW: 79, rotateCCW: 80, press: 90)
    // kVK_F13 / kVK_F14 / kVK_F15.
    public static let defaultFunctionKeys = KnobKeyCodes(rotateCW: 105, rotateCCW: 107, press: 113)
    // kVK_F13...kVK_F20: keys no Mac keyboard has, so swallowing them never affects typing.
    public static let allowedFunctionKeys: Set<UInt16> = [105, 107, 113, 106, 64, 79, 80, 90]

    public func input(forKeyCode code: UInt16) -> KnobInput? {
        switch code {
        case rotateCW: .rotateCW
        case rotateCCW: .rotateCCW
        case press: .press
        default: nil
        }
    }

    public func keyCode(for input: KnobInput) -> UInt16 {
        switch input {
        case .rotateCW: rotateCW
        case .rotateCCW: rotateCCW
        case .press: press
        }
    }

    public var all: Set<UInt16> { [rotateCW, rotateCCW, press] }
}

public struct DeviceMatch: Codable, Equatable, Sendable {
    public var vendorID: Int = 0x3554
    public var productID: Int = 0xFA07
    public init() {}
}

public struct InputConfig: Codable, Equatable, Sendable {
    public var source: InputSource = .consumerRemap
    public var knobMaxHoldMs: Double = 60
    public var knobBurstMaxHoldMs: Double = 150
    public var knobBurstWindowMs: Double = 300
    public var functionKeyCodes: KnobKeyCodes = .defaultFunctionKeys
    public init() {}

    public var watchedKeyCodes: KnobKeyCodes {
        source == .consumerRemap ? .remapped : functionKeyCodes
    }
}

public struct ScrollConfig: Codable, Equatable, Sendable {
    public var slowPixels: Double = 40
    public var mediumPixels: Double = 100
    public var fastPixels: Double = 250
    public var animationMs: Double = 120
    public var accelerationThresholdMs: Double = 60
    public var accelerationFullMs: Double = 30
    public var maxAcceleration: Double = 3
    public var invert: Bool = false
    public init() {}

    public func pixels(for speed: ScrollSpeed) -> Double {
        switch speed {
        case .slow: slowPixels
        case .medium: mediumPixels
        case .fast: fastPixels
        }
    }
}

public struct HUDConfig: Codable, Equatable, Sendable {
    public var displaySeconds: Double = 1.0
    public var pickerAutoSelectSeconds: Double = 1.5
    public init() {}
}

public struct Binding: Codable, Equatable, Sendable {
    public var gesture: KnobInput
    public var modifiers: ModifierSet
    public var action: Action

    public init(_ gesture: KnobInput, _ modifiers: ModifierSet, _ action: Action) {
        self.gesture = gesture
        self.modifiers = modifiers
        self.action = action
    }

    public init(_ gesture: KnobInput, _ action: Action) {
        self.init(gesture, [], action)
    }

    private enum CodingKeys: String, CodingKey { case gesture, modifiers, action }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gesture = try c.decode(KnobInput.self, forKey: .gesture)
        modifiers = try c.decodeIfPresent(ModifierSet.self, forKey: .modifiers) ?? []
        action = try c.decode(Action.self, forKey: .action)
    }
}

public struct ModeConfig: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// SF Symbol name shown in the HUD and menu bar.
    public var symbol: String
    public var bindings: [Binding]

    public init(id: String, name: String, symbol: String, bindings: [Binding]) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.bindings = bindings
    }

    /// Exact modifier match wins; otherwise the binding without modifiers is used.
    public func action(for gesture: KnobInput, modifiers: ModifierSet) -> Action {
        if let exact = bindings.first(where: { $0.gesture == gesture && $0.modifiers == modifiers }) {
            return exact.action
        }
        return bindings.first(where: { $0.gesture == gesture && $0.modifiers.isEmpty })?.action ?? .none
    }
}

public struct ConfigError: Error, Equatable, CustomStringConvertible {
    public let description: String
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var device = DeviceMatch()
    public var input = InputConfig()
    public var doublePressWindowMs: Double = 250
    public var scroll = ScrollConfig()
    public var hud = HUDConfig()
    public var modes: [ModeConfig] = AppConfig.defaultModes
    public init() {}

    public static let defaultModes: [ModeConfig] = [
        ModeConfig(id: "volume", name: "Volume", symbol: "speaker.wave.2.fill", bindings: [
            Binding(.rotateCW, .volumeUp(fine: false)),
            Binding(.rotateCCW, .volumeDown(fine: false)),
            Binding(.rotateCW, .option, .volumeUp(fine: true)),
            Binding(.rotateCCW, .option, .volumeDown(fine: true)),
            Binding(.press, .mute),
        ]),
        ModeConfig(id: "scroll", name: "Scroll", symbol: "arrow.up.and.down.text.horizontal", bindings: [
            Binding(.rotateCW, .scroll(direction: .down, scale: 1)),
            Binding(.rotateCCW, .scroll(direction: .up, scale: 1)),
            Binding(.rotateCW, .shift, .scroll(direction: .right, scale: 1)),
            Binding(.rotateCCW, .shift, .scroll(direction: .left, scale: 1)),
            Binding(.rotateCW, .option, .scroll(direction: .down, scale: 0.25)),
            Binding(.rotateCCW, .option, .scroll(direction: .up, scale: 0.25)),
            // kVK_ANSI_Equal / kVK_ANSI_Minus: Cmd+= zooms in, Cmd+- zooms out.
            Binding(.rotateCW, .command, .key(code: 24, modifiers: .command, repeatCount: 1)),
            Binding(.rotateCCW, .command, .key(code: 27, modifiers: .command, repeatCount: 1)),
            Binding(.press, .cycleScrollSpeed),
        ]),
        // kVK_RightArrow / kVK_LeftArrow seek in most players (YouTube, QuickTime, IINA, VLC).
        ModeConfig(id: "media", name: "Media", symbol: "playpause.fill", bindings: [
            Binding(.rotateCW, .key(code: 124, modifiers: [], repeatCount: 1)),
            Binding(.rotateCCW, .key(code: 123, modifiers: [], repeatCount: 1)),
            Binding(.rotateCW, .shift, .key(code: 124, modifiers: [], repeatCount: 3)),
            Binding(.rotateCCW, .shift, .key(code: 123, modifiers: [], repeatCount: 3)),
            Binding(.press, .mediaPlayPause),
        ]),
    ]

    public func validate() throws {
        if modes.isEmpty { throw ConfigError(description: "modes must not be empty") }
        var seen = Set<String>()
        for mode in modes {
            if !seen.insert(mode.id).inserted {
                throw ConfigError(description: "duplicate mode id \"\(mode.id)\"")
            }
            for binding in mode.bindings {
                if case .key(_, _, let count) = binding.action, count < 1 || count > 20 {
                    throw ConfigError(description: "mode \"\(mode.id)\": key repeat must be 1...20")
                }
                if case .scroll(_, let scale) = binding.action, !(scale > 0) {
                    throw ConfigError(description: "mode \"\(mode.id)\": scroll scale must be > 0")
                }
            }
        }
        if !(input.knobMaxHoldMs > 0) { throw ConfigError(description: "input.knobMaxHoldMs must be > 0") }
        if !(input.knobBurstMaxHoldMs >= input.knobMaxHoldMs) {
            throw ConfigError(description: "input.knobBurstMaxHoldMs must be >= knobMaxHoldMs")
        }
        if !(input.knobBurstWindowMs >= 0) { throw ConfigError(description: "input.knobBurstWindowMs must be >= 0") }
        if !(doublePressWindowMs > 0) { throw ConfigError(description: "doublePressWindowMs must be > 0") }
        if !(scroll.slowPixels > 0 && scroll.mediumPixels > 0 && scroll.fastPixels > 0) {
            throw ConfigError(description: "scroll pixels must be > 0")
        }
        if !(scroll.animationMs >= 0) { throw ConfigError(description: "scroll.animationMs must be >= 0") }
        if !(scroll.maxAcceleration >= 1) { throw ConfigError(description: "scroll.maxAcceleration must be >= 1") }
        if !(scroll.accelerationThresholdMs >= 0 && scroll.accelerationFullMs >= 0) {
            throw ConfigError(description: "scroll acceleration timings must be >= 0")
        }
        if !(hud.displaySeconds > 0) { throw ConfigError(description: "hud.displaySeconds must be > 0") }
        if !(hud.pickerAutoSelectSeconds > 0) {
            throw ConfigError(description: "hud.pickerAutoSelectSeconds must be > 0")
        }
        if input.source == .functionKeys {
            let codes = input.functionKeyCodes.all
            if codes.count != 3 {
                throw ConfigError(description: "input.functionKeyCodes must be three different key codes")
            }
            if !codes.isSubset(of: KnobKeyCodes.allowedFunctionKeys) {
                throw ConfigError(description: "input.functionKeyCodes must be F13-F20 key codes")
            }
        }
        let watched = input.watchedKeyCodes.all
        for mode in modes {
            for binding in mode.bindings {
                if case .key(let code, _, _) = binding.action, watched.contains(code) {
                    throw ConfigError(description: "mode \"\(mode.id)\": key \(code) is a knob key code")
                }
            }
        }
    }

    public static func decode(_ data: Data) throws -> AppConfig {
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        try config.validate()
        return config
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

// Missing keys fall back to defaults so a hand-edited config only needs what it changes.
extension DeviceMatch {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vendorID = try c.decodeIfPresent(Int.self, forKey: .vendorID) ?? vendorID
        productID = try c.decodeIfPresent(Int.self, forKey: .productID) ?? productID
    }
}

extension InputConfig {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(InputSource.self, forKey: .source) ?? source
        knobMaxHoldMs = try c.decodeIfPresent(Double.self, forKey: .knobMaxHoldMs) ?? knobMaxHoldMs
        knobBurstMaxHoldMs = try c.decodeIfPresent(Double.self, forKey: .knobBurstMaxHoldMs) ?? knobBurstMaxHoldMs
        knobBurstWindowMs = try c.decodeIfPresent(Double.self, forKey: .knobBurstWindowMs) ?? knobBurstWindowMs
        functionKeyCodes = try c.decodeIfPresent(KnobKeyCodes.self, forKey: .functionKeyCodes) ?? functionKeyCodes
    }
}

extension ScrollConfig {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slowPixels = try c.decodeIfPresent(Double.self, forKey: .slowPixels) ?? slowPixels
        mediumPixels = try c.decodeIfPresent(Double.self, forKey: .mediumPixels) ?? mediumPixels
        fastPixels = try c.decodeIfPresent(Double.self, forKey: .fastPixels) ?? fastPixels
        animationMs = try c.decodeIfPresent(Double.self, forKey: .animationMs) ?? animationMs
        accelerationThresholdMs = try c.decodeIfPresent(Double.self, forKey: .accelerationThresholdMs)
            ?? accelerationThresholdMs
        accelerationFullMs = try c.decodeIfPresent(Double.self, forKey: .accelerationFullMs) ?? accelerationFullMs
        maxAcceleration = try c.decodeIfPresent(Double.self, forKey: .maxAcceleration) ?? maxAcceleration
        invert = try c.decodeIfPresent(Bool.self, forKey: .invert) ?? invert
    }
}

extension HUDConfig {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displaySeconds = try c.decodeIfPresent(Double.self, forKey: .displaySeconds) ?? displaySeconds
        pickerAutoSelectSeconds = try c.decodeIfPresent(Double.self, forKey: .pickerAutoSelectSeconds)
            ?? pickerAutoSelectSeconds
    }
}

extension AppConfig {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        device = try c.decodeIfPresent(DeviceMatch.self, forKey: .device) ?? device
        input = try c.decodeIfPresent(InputConfig.self, forKey: .input) ?? input
        doublePressWindowMs = try c.decodeIfPresent(Double.self, forKey: .doublePressWindowMs) ?? doublePressWindowMs
        scroll = try c.decodeIfPresent(ScrollConfig.self, forKey: .scroll) ?? scroll
        hud = try c.decodeIfPresent(HUDConfig.self, forKey: .hud) ?? hud
        modes = try c.decodeIfPresent([ModeConfig].self, forKey: .modes) ?? modes
    }
}
