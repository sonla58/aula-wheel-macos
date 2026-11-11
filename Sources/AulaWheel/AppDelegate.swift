import AppKit
import AulaWheelCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum DefaultsKey {
        static let enabled = "enabled"
        static let modeID = "currentModeID"
        static let scrollSpeed = "scrollSpeed"
    }

    private let defaults = UserDefaults.standard
    let store: ConfigStore
    private let tap = EventTap()
    let hid = HIDMonitor()
    private let poster = EventPoster()
    let hud = HUDController()
    lazy var setup = SetupWindowController(environment: SetupEnvironment(
        modes: { [unowned self] in controller.modes },
        keyboardConnected: { [unowned self] in hid.isConnected },
        appEnabled: { [unowned self] in enabled },
        enableApp: { [unowned self] in
            enabled = true
            activate()
            updateStatusIcon()
        }))

    private(set) var config: AppConfig
    var configError: String?
    private var remapper: KeyRemapper
    private var classifier: KnobClassifier
    private var recognizer: GestureRecognizer
    var controller: ModeController
    private var planner: ScrollPlanner
    private let scroller: ScrollEngine

    var statusItem: NSStatusItem!
    private var deadlineTimer: Timer?
    /// The remap is only ever on while this is true; it is cleared before anything else on disable.
    private var remapWanted = false
    private var remapRefresh: DispatchWorkItem?
    private var hadInputMonitoring = false
    private var signalSources: [DispatchSourceSignal] = []

    override init() {
        let store = ConfigStore()
        var loaded = AppConfig()
        var loadError: String?
        do { loaded = try store.load() } catch { loadError = "\(error)" }
        self.store = store
        config = loaded
        configError = loadError
        remapper = KeyRemapper(device: loaded.device)
        classifier = Self.makeClassifier(loaded.input)
        recognizer = GestureRecognizer(doublePressWindow: loaded.doublePressWindowMs / 1000)
        controller = ModeController(
            modes: loaded.modes,
            currentModeID: UserDefaults.standard.string(forKey: DefaultsKey.modeID),
            scrollSpeed: ScrollSpeed(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.scrollSpeed) ?? "")
                ?? .medium,
            pickerAutoSelect: loaded.hud.pickerAutoSelectSeconds
        )
        planner = ScrollPlanner(config: loaded.scroll)
        scroller = ScrollEngine(poster: poster, duration: loaded.scroll.animationMs / 1000)
        super.init()
        hud.displaySeconds = loaded.hud.displaySeconds
    }

    private static func makeClassifier(_ input: InputConfig) -> KnobClassifier {
        KnobClassifier(
            maxHold: input.knobMaxHoldMs / 1000,
            burstMaxHold: input.knobBurstMaxHoldMs / 1000,
            burstWindow: input.knobBurstWindowMs / 1000)
    }

    var enabled: Bool {
        get { defaults.object(forKey: DefaultsKey.enabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: DefaultsKey.enabled) }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A previous crash can leave the knob remapped with nobody listening.
        remapper.clear()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        installSignalHandlers()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        tap.onKey = { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) }
        }
        hid.onConnect = { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRemapRefresh() }
        }
        hid.onVendorPing = { [weak self] in
            MainActor.assumeIsolated { self?.handleVendorPing() }
        }
        store.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.reloadConfig(force: false) }
        }
        store.startWatching()

        hadInputMonitoring = Permissions.inputMonitoring

        startHID()
        activate()
        updateStatusIcon()
        setup.showIfNeeded()

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHealth() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) {
        deactivate()
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    @objc private func didWake() {
        scheduleRemapRefresh()
    }

    // MARK: - Activation

    func activate() {
        guard enabled, Permissions.accessibility else { return }
        classifier.reset()
        recognizer.reset()
        tap.watchedKeyCodes = config.input.watchedKeyCodes.all
        guard tap.start() else {
            setRemap(false)
            return
        }
        setRemap(config.input.source == .consumerRemap)
    }

    func deactivate() {
        setRemap(false)
        tap.stop()
        resetInputState()
    }

    private func setRemap(_ wanted: Bool) {
        remapWanted = wanted
        remapRefresh?.cancel()
        remapRefresh = nil
        let ok = wanted ? remapper.apply() : remapper.clear()
        Log.remap.notice("remap \(wanted ? "apply" : "clear", privacy: .public) ok=\(ok, privacy: .public)")
    }

    private func resetInputState() {
        classifier.reset()
        recognizer.reset()
        scroller.stop()
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        if controller.isPickerOpen {
            apply(controller.selectMode(id: controller.currentMode.id))
        }
    }

    private func startHID() {
        hid.start(device: config.device)
    }

    /// The remap is attached to the HID service, which is recreated on every reconnect.
    private func scheduleRemapRefresh() {
        guard remapWanted else { return }
        remapRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.remapWanted, self.tap.isRunning else { return }
                let ok = self.remapper.apply()
                Log.remap.notice("remap refresh ok=\(ok, privacy: .public)")
            }
        }
        remapRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func checkHealth() {
        if !Permissions.accessibility {
            if tap.isRunning || remapWanted { deactivate() }
        } else if enabled && !tap.isRunning {
            activate()
        } else if remapWanted && remapper.isApplied() == false {
            // A reconnect raced the refresh, or something else rewrote the device's mapping.
            let ok = remapper.apply()
            Log.remap.notice("remap missing, re-applied ok=\(ok, privacy: .public)")
        }
        let inputMonitoring = Permissions.inputMonitoring
        if inputMonitoring && !hadInputMonitoring {
            startHID()
        }
        hadInputMonitoring = inputMonitoring
        updateStatusIcon()
    }

    func reloadConfig(force: Bool) {
        let newConfig: AppConfig
        do {
            newConfig = try store.load()
        } catch {
            configError = "\(error)"
            hud.showBanner(symbol: "exclamationmark.triangle.fill", title: "Config error", subtitle: "Kept previous config")
            return
        }
        configError = nil
        guard force || newConfig != config else { return }

        deactivate()
        let deviceChanged = newConfig.device != config.device
        config = newConfig
        remapper = KeyRemapper(device: config.device)
        classifier = Self.makeClassifier(config.input)
        recognizer = GestureRecognizer(doublePressWindow: config.doublePressWindowMs / 1000)
        controller.replaceModes(config.modes)
        controller.pickerAutoSelect = config.hud.pickerAutoSelectSeconds
        planner = ScrollPlanner(config: config.scroll)
        scroller.duration = config.scroll.animationMs / 1000
        hud.displaySeconds = config.hud.displaySeconds
        if deviceChanged { startHID() }
        activate()
        updateStatusIcon()
        hud.showBanner(symbol: "arrow.clockwise", title: "Config reloaded", subtitle: nil)
    }

    // MARK: - Input pipeline

    private func handleKey(_ event: EventTap.KeyEvent) {
        guard event.generation == tap.generation,
              let input = config.input.watchedKeyCodes.input(forKeyCode: event.keyCode) else { return }
        let modifiers = ModifierSet(eventFlags: event.flags)
        let time = Clock.eventTime(event.timestamp)
        Log.input.debug("""
            key \(input.rawValue, privacy: .public) \(event.isDown ? "down" : "up", privacy: .public) \
            repeat=\(event.isRepeat, privacy: .public) t=\(time, format: .fixed(precision: 4), privacy: .public)
            """)

        if config.input.source == .functionKeys {
            if event.isDown && !event.isRepeat {
                process([.knob(input, modifiers, time: time)])
            }
        } else {
            process(classifier.handle(
                KnobKeyEvent(input, isDown: event.isDown, isRepeat: event.isRepeat, modifiers: modifiers, time: time)))
        }
        reschedule()
    }

    private func handleVendorPing() {
        let effects = controller.vendorPing()
        guard !effects.isEmpty else { return }
        recognizer.reset()
        apply(effects)
        reschedule()
    }

    private func process(_ events: [ClassifiedEvent]) {
        for event in events {
            switch event {
            case .functionKey(let input, let modifiers):
                Log.input.notice("classified as F-key: \(input.rawValue, privacy: .public)")
                poster.postSystemKey(systemKey(for: input), modifiers: modifiers)
            case .knob(let input, let modifiers, let time):
                for gesture in recognizer.handle(input, modifiers: modifiers, time: time) {
                    setup.record(gesture)
                    apply(controller.handle(gesture, now: Clock.now()))
                }
            }
        }
    }

    private func systemKey(for input: KnobInput) -> SystemKey {
        switch input {
        case .rotateCW: .soundUp
        case .rotateCCW: .soundDown
        case .press: .mute
        }
    }

    private func reschedule() {
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        let deadlines = [classifier.nextDeadline, recognizer.nextDeadline, controller.nextDeadline].compactMap { $0 }
        guard let next = deadlines.min() else { return }
        let timer = Timer(timeInterval: max(next - Clock.now(), 0) + 0.001, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.onDeadline() }
        }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        deadlineTimer = timer
    }

    private func onDeadline() {
        let now = Clock.now()
        let codes = config.input.watchedKeyCodes
        process(classifier.tick(now: now) { input in
            let down = CGEventSource.keyState(.hidSystemState, key: codes.keyCode(for: input))
            Log.input.debug("tick \(input.rawValue, privacy: .public) keyState=\(down, privacy: .public)")
            return down
        })
        for gesture in recognizer.tick(now: now) {
            setup.record(gesture)
            apply(controller.handle(gesture, now: now))
        }
        apply(controller.tick(now: now))
        reschedule()
    }

    func apply(_ effects: [ModeEffect]) {
        setup.record(effects)
        for effect in effects {
            switch effect {
            case .perform(let action, let time):
                perform(action, time: time)
            case .showMode(let mode):
                hud.showBanner(symbol: mode.symbol, title: mode.name, subtitle: speedSubtitle(for: mode))
            case .showScrollSpeed(let speed):
                hud.showBanner(symbol: symbol(for: speed), title: "Scroll speed", subtitle: speed.rawValue.capitalized)
            case .showRGB:
                hud.showBanner(symbol: "rainbow", title: "RGB", subtitle: "Knob controls the lights")
            case .showPicker(let modes, let highlighted):
                hud.showPicker(
                    items: modes.map { PickerItem(id: $0.id, symbol: $0.symbol, title: $0.name) },
                    highlighted: highlighted)
            case .closePicker:
                hud.hide()
            case .stateChanged:
                defaults.set(controller.currentMode.id, forKey: DefaultsKey.modeID)
                defaults.set(controller.scrollSpeed.rawValue, forKey: DefaultsKey.scrollSpeed)
                updateStatusIcon()
            }
        }
        recognizer.doublePressEnabled = !controller.isPickerOpen
    }

    private func perform(_ action: Action, time: TimeInterval) {
        switch action {
        case .none, .cycleScrollSpeed:
            break
        case .volumeUp(let fine):
            poster.postSystemKey(.soundUp, modifiers: fine ? [.shift, .option] : [])
        case .volumeDown(let fine):
            poster.postSystemKey(.soundDown, modifiers: fine ? [.shift, .option] : [])
        case .mute:
            poster.postSystemKey(.mute, modifiers: [])
        case .scroll(let direction, let scale):
            let delta = planner.delta(direction: direction, scale: scale, speed: controller.scrollSpeed, time: time)
            scroller.add(dx: delta.dx, dy: delta.dy)
        case .key(let code, let modifiers, let repeatCount):
            poster.postKey(code: code, modifiers: modifiers, repeatCount: repeatCount)
        case .mediaPlayPause:
            poster.postSystemKey(.play, modifiers: [])
        case .mediaNext:
            poster.postSystemKey(.next, modifiers: [])
        case .mediaPrevious:
            poster.postSystemKey(.previous, modifiers: [])
        }
    }

    private func speedSubtitle(for mode: ModeConfig) -> String? {
        let scrolls = mode.bindings.contains {
            if case .scroll = $0.action { return true }
            return false
        }
        return scrolls ? "Speed: \(controller.scrollSpeed.rawValue.capitalized)" : nil
    }

    private func symbol(for speed: ScrollSpeed) -> String {
        switch speed {
        case .slow: "tortoise.fill"
        case .medium: "figure.walk"
        case .fast: "hare.fill"
        }
    }
}
