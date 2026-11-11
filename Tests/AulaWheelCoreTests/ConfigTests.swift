import Foundation
import Testing
@testable import AulaWheelCore

@Suite struct ConfigTests {
    @Test func defaultConfigRoundTrips() throws {
        let data = try AppConfig().encoded()
        #expect(try AppConfig.decode(data) == AppConfig())
    }

    @Test func partialConfigFallsBackToDefaults() throws {
        let json = #"{"scroll": {"fastPixels": 400}, "input": {"knobMaxHoldMs": 35}}"#
        let config = try AppConfig.decode(Data(json.utf8))
        #expect(config.scroll.fastPixels == 400)
        #expect(config.scroll.slowPixels == ScrollConfig().slowPixels)
        #expect(config.input.knobMaxHoldMs == 35)
        #expect(config.input.source == .consumerRemap)
        #expect(config.modes == AppConfig.defaultModes)
    }

    @Test func unknownProductFromSameVendorIsUnverified() {
        let device = DeviceMatch()
        #expect(device.support(vendorID: 0x3554, productID: 0xFA09, sendsVolumeKeys: false) == .verified)
        #expect(device.support(vendorID: 0x3554, productID: 0xFA08, sendsVolumeKeys: true) == .unverified)
        #expect(device.support(vendorID: 0x3554, productID: 0xFA08, sendsVolumeKeys: false) == nil)
        #expect(device.support(vendorID: 0x05AC, productID: 0x0343, sendsVolumeKeys: true) == nil)
    }

    @Test func legacySingleProductIDKeepsKnownIDs() throws {
        let json = #"{"device": {"productID": 4660}}"#
        #expect(try AppConfig.decode(Data(json.utf8)).device.productIDs == DeviceMatch.knownProductIDs + [0x1234])
    }

    @Test func actionsRoundTrip() throws {
        let actions: [Action] = [
            .none, .volumeUp(fine: true), .volumeDown(fine: false), .mute,
            .scroll(direction: .left, scale: 0.5), .key(code: 124, modifiers: [.command, .shift], repeatCount: 3),
            .mediaPlayPause, .mediaNext, .mediaPrevious, .cycleScrollSpeed,
        ]
        let data = try JSONEncoder().encode(actions)
        #expect(try JSONDecoder().decode([Action].self, from: data) == actions)
    }

    @Test func unknownActionTypeIsRejected() {
        let json = #"{"type": "explode"}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Action.self, from: Data(json.utf8)) }
    }

    @Test func unknownModifierIsRejected() {
        let json = #"["shift", "hyper"]"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ModifierSet.self, from: Data(json.utf8)) }
    }

    @Test func modifiersMapFromEventFlags() {
        let flags: UInt64 = 0x0002_0000 | 0x0010_0000 | 0x0080_0000
        #expect(ModifierSet(eventFlags: flags) == [.shift, .command])
        #expect(ModifierSet([.option, .control]).eventFlags == 0x0008_0000 | 0x0004_0000)
    }

    @Test func validationRejectsBadConfigs() {
        var duplicate = AppConfig()
        duplicate.modes.append(duplicate.modes[0])
        #expect(throws: ConfigError.self) { try duplicate.validate() }

        var empty = AppConfig()
        empty.modes = []
        #expect(throws: ConfigError.self) { try empty.validate() }

        var noDevice = AppConfig()
        noDevice.device.productIDs = []
        #expect(throws: ConfigError.self) { try noDevice.validate() }

        var badHold = AppConfig()
        badHold.input.knobMaxHoldMs = 0
        #expect(throws: ConfigError.self) { try badHold.validate() }

        var badRepeat = AppConfig()
        badRepeat.modes[0].bindings = [Binding(.press, .key(code: 1, modifiers: [], repeatCount: 0))]
        #expect(throws: ConfigError.self) { try badRepeat.validate() }

        var typingKeys = AppConfig()
        typingKeys.input.source = .functionKeys
        typingKeys.input.functionKeyCodes = KnobKeyCodes(rotateCW: 0, rotateCCW: 1, press: 2)
        #expect(throws: ConfigError.self) { try typingKeys.validate() }

        var loopingKey = AppConfig()
        loopingKey.modes[0].bindings = [Binding(.press, .key(code: 79, modifiers: [], repeatCount: 1))]
        #expect(throws: ConfigError.self) { try loopingKey.validate() }

        var instantPicker = AppConfig()
        instantPicker.hud.pickerAutoSelectSeconds = 0
        #expect(throws: ConfigError.self) { try instantPicker.validate() }

        var sameKeys = AppConfig()
        sameKeys.input.source = .functionKeys
        sameKeys.input.functionKeyCodes = KnobKeyCodes(rotateCW: 1, rotateCCW: 1, press: 2)
        #expect(throws: ConfigError.self) { try sameKeys.validate() }
    }

    @Test func bindingResolutionPrefersExactModifiersThenFallsBack() {
        let mode = ModeConfig(id: "m", name: "M", symbol: "x", bindings: [
            Binding(.rotateCW, .volumeUp(fine: false)),
            Binding(.rotateCW, .option, .volumeUp(fine: true)),
        ])
        #expect(mode.action(for: .rotateCW, modifiers: .option) == .volumeUp(fine: true))
        #expect(mode.action(for: .rotateCW, modifiers: .shift) == .volumeUp(fine: false))
        #expect(mode.action(for: .rotateCW, modifiers: [.option, .shift]) == .volumeUp(fine: false))
        #expect(mode.action(for: .press, modifiers: []) == .none)
    }

    @Test func watchedKeyCodesFollowInputSource() {
        var input = InputConfig()
        #expect(input.watchedKeyCodes == .remapped)
        input.source = .functionKeys
        #expect(input.watchedKeyCodes == .defaultFunctionKeys)
        #expect(KnobKeyCodes.remapped.input(forKeyCode: 80) == .rotateCCW)
        #expect(KnobKeyCodes.remapped.input(forKeyCode: 12) == nil)
    }

    @Test func scrollSpeedCycles() {
        #expect(ScrollSpeed.slow.next == .medium)
        #expect(ScrollSpeed.medium.next == .fast)
        #expect(ScrollSpeed.fast.next == .slow)
    }

    @Test func remapMergeKeepsOtherMappings() {
        typealias E = ConsumerRemap.Entry
        let userRemap = E(source: 0x7_0000_0039, destination: 0x7_0000_00E0)
        let stale = E(source: 0xC_0000_00E9, destination: 0x7_0000_0001)
        let applied = ConsumerRemap.updated([userRemap, stale], applying: true, source: { $0.source }, make: { $0 })
        #expect(applied == [userRemap] + ConsumerRemap.entries)
        let cleared = ConsumerRemap.updated(applied, applying: false, source: { $0.source }, make: { $0 })
        #expect(cleared == [userRemap])
        let unknown: [E?] = [nil]
        #expect(ConsumerRemap.updated(unknown, applying: false, source: { $0?.source }, make: { $0 }).count == 1)
    }
}
