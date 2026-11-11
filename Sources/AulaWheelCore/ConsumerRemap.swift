/// The per-device key remap that turns the AULA's Consumer Volume/Mute codes into F18/F19/F20.
public enum ConsumerRemap {
    public struct Entry: Equatable, Sendable {
        public var source: UInt64
        public var destination: UInt64
    }

    // Consumer page (0x0C) Volume Up / Volume Down / Mute -> keyboard page (0x07) F18 / F19 / F20.
    public static let entries: [Entry] = [
        Entry(source: 0xC_0000_00E9, destination: 0x7_0000_006D),
        Entry(source: 0xC_0000_00EA, destination: 0x7_0000_006E),
        Entry(source: 0xC_0000_00E2, destination: 0x7_0000_006F),
    ]

    /// Returns `existing` with this app's entries added (`applying`) or removed, leaving every
    /// other mapping on the device (e.g. the user's own modifier remaps) untouched.
    public static func updated<Item>(
        _ existing: [Item], applying: Bool, source: (Item) -> UInt64?, make: (Entry) -> Item
    ) -> [Item] {
        let ours = Set(entries.map(\.source))
        let others = existing.filter { item in source(item).map { !ours.contains($0) } ?? true }
        return applying ? others + entries.map(make) : others
    }
}
