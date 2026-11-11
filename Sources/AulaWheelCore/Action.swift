public enum ScrollDirection: String, Codable, Sendable {
    case up, down, left, right
}

/// What a knob gesture does inside a mode.
public enum Action: Equatable, Sendable {
    case none
    case volumeUp(fine: Bool)
    case volumeDown(fine: Bool)
    case mute
    case scroll(direction: ScrollDirection, scale: Double)
    case key(code: UInt16, modifiers: ModifierSet, repeatCount: Int)
    case mediaPlayPause
    case mediaNext
    case mediaPrevious
    case cycleScrollSpeed
}

extension Action: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, fine, direction, scale, keyCode, modifiers, `repeat`
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "none": self = .none
        case "volumeUp": self = .volumeUp(fine: try c.decodeIfPresent(Bool.self, forKey: .fine) ?? false)
        case "volumeDown": self = .volumeDown(fine: try c.decodeIfPresent(Bool.self, forKey: .fine) ?? false)
        case "mute": self = .mute
        case "scroll":
            self = .scroll(
                direction: try c.decode(ScrollDirection.self, forKey: .direction),
                scale: try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1)
        case "key":
            self = .key(
                code: try c.decode(UInt16.self, forKey: .keyCode),
                modifiers: try c.decodeIfPresent(ModifierSet.self, forKey: .modifiers) ?? [],
                repeatCount: try c.decodeIfPresent(Int.self, forKey: .repeat) ?? 1)
        case "mediaPlayPause": self = .mediaPlayPause
        case "mediaNext": self = .mediaNext
        case "mediaPrevious": self = .mediaPrevious
        case "cycleScrollSpeed": self = .cycleScrollSpeed
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "Unknown action type \"\(type)\"")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none: try c.encode("none", forKey: .type)
        case .volumeUp(let fine):
            try c.encode("volumeUp", forKey: .type)
            if fine { try c.encode(true, forKey: .fine) }
        case .volumeDown(let fine):
            try c.encode("volumeDown", forKey: .type)
            if fine { try c.encode(true, forKey: .fine) }
        case .mute: try c.encode("mute", forKey: .type)
        case .scroll(let direction, let scale):
            try c.encode("scroll", forKey: .type)
            try c.encode(direction, forKey: .direction)
            if scale != 1 { try c.encode(scale, forKey: .scale) }
        case .key(let code, let modifiers, let repeatCount):
            try c.encode("key", forKey: .type)
            try c.encode(code, forKey: .keyCode)
            if !modifiers.isEmpty { try c.encode(modifiers, forKey: .modifiers) }
            if repeatCount != 1 { try c.encode(repeatCount, forKey: .repeat) }
        case .mediaPlayPause: try c.encode("mediaPlayPause", forKey: .type)
        case .mediaNext: try c.encode("mediaNext", forKey: .type)
        case .mediaPrevious: try c.encode("mediaPrevious", forKey: .type)
        case .cycleScrollSpeed: try c.encode("cycleScrollSpeed", forKey: .type)
        }
    }
}
