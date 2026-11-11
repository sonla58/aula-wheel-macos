/// Keyboard modifiers that can be combined with knob gestures.
public struct ModifierSet: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let shift = ModifierSet(rawValue: 1 << 0)
    public static let control = ModifierSet(rawValue: 1 << 1)
    public static let option = ModifierSet(rawValue: 1 << 2)
    public static let command = ModifierSet(rawValue: 1 << 3)

    // Device-independent bits of CGEventFlags / NSEvent.ModifierFlags.
    private static let flagBits: [(ModifierSet, UInt64)] = [
        (.shift, 0x0002_0000),
        (.control, 0x0004_0000),
        (.option, 0x0008_0000),
        (.command, 0x0010_0000),
    ]

    static let names: [(String, ModifierSet)] = [
        ("shift", .shift), ("control", .control), ("option", .option), ("command", .command),
    ]

    public init(eventFlags: UInt64) {
        var set: ModifierSet = []
        for (modifier, bit) in Self.flagBits where eventFlags & bit != 0 {
            set.insert(modifier)
        }
        self = set
    }

    public var eventFlags: UInt64 {
        Self.flagBits.reduce(0) { contains($1.0) ? $0 | $1.1 : $0 }
    }
}

extension ModifierSet: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let names = try container.decode([String].self)
        var set: ModifierSet = []
        for name in names {
            guard let match = Self.names.first(where: { $0.0 == name.lowercased() }) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unknown modifier \"\(name)\"")
            }
            set.insert(match.1)
        }
        self = set
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.names.filter { contains($0.1) }.map(\.0))
    }
}
