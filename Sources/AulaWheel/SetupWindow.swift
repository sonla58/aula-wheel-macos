import AppKit
import AulaWheelCore
import ServiceManagement
import SwiftUI

/// What the setup window needs from the rest of the app.
@MainActor
struct SetupEnvironment {
    var modes: () -> [ModeConfig]
    var keyboardConnected: () -> Bool
    var appEnabled: () -> Bool
    var enableApp: () -> Void
}

@MainActor
final class SetupModel: ObservableObject {
    @Published var step: SetupStep = .welcome
    @Published var status = Permissions.status
    @Published var appEnabled = true
    @Published var practice = KnobPractice()
    @Published var knobInRGB = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var launchAtLoginError: String?
    @Published var modes: [ModeConfig] = []
    /// Set once a guide was opened, so the relaunch hint only shows to someone who tried.
    @Published var triedGranting = false

    var canContinue: Bool { SetupFlow.canContinue(from: step, status: status) }
    var canSkip: Bool { SetupFlow.canSkip(step) }
}

@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    private static let completedKey = "setupCompleted"

    private let environment: SetupEnvironment
    private let model = SetupModel()
    private let guide = SettingsGuide()
    private var window: NSWindow?
    private var timer: Timer?

    init(environment: SetupEnvironment) {
        self.environment = environment
        super.init()
        guide.onGranted = { [weak self] in self?.bringToFront() }
    }

    private var completed: Bool {
        get { UserDefaults.standard.bool(forKey: Self.completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.completedKey) }
    }

    var isVisible: Bool { window?.isVisible == true }

    /// Opens the window at launch only for first-run setup or a missing permission.
    func showIfNeeded() {
        guard let step = SetupFlow.launchStep(completed: completed, status: Permissions.status) else { return }
        show(step: step)
    }

    func show(step: SetupStep) {
        model.step = step
        model.practice = KnobPractice()
        model.knobInRGB = false
        refresh()
        let window = window ?? makeWindow()
        self.window = window
        startPolling()
        bringToFront()
    }

    // MARK: - Knob feedback

    func record(_ gesture: KnobGesture) {
        guard isVisible, model.step == .tryIt else { return }
        model.practice.record(gesture)
        model.knobInRGB = false
    }

    func record(_ effects: [ModeEffect]) {
        guard isVisible, model.step == .tryIt else { return }
        model.practice.record(effects)
        if effects.contains(.showRGB) { model.knobInRGB = true }
    }

    // MARK: - Actions

    private func perform(_ action: SetupAction) {
        switch action {
        case .next:
            guard model.canContinue else { return }
            advance()
        case .skip:
            guard model.canSkip else { return }
            advance()
        case .back:
            if let previous = SetupStep(rawValue: model.step.rawValue - 1) { model.step = previous }
        case .grant(let permission):
            model.triedGranting = true
            guide.start(permission)
        case .relaunch:
            Permissions.relaunch()
        case .openBluetooth:
            Permissions.openBluetoothSettings()
        case .enableApp:
            environment.enableApp()
            refresh()
        case .setLaunchAtLogin(let on):
            setLaunchAtLogin(on)
        }
    }

    private func advance() {
        if let next = SetupStep(rawValue: model.step.rawValue + 1) {
            model.step = next
        } else {
            finish()
        }
    }

    private func finish() {
        completed = true
        window?.close()
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            model.launchAtLoginError = nil
        } catch {
            model.launchAtLoginError = error.localizedDescription
        }
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Window

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AulaWheel Setup"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        let hosting = NSHostingController(
            rootView: SetupView(model: model) { [weak self] action in self?.perform(action) })
        // Left on, it adds the title bar's safe area to the size and the window ends up too tall.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 560, height: 600))
        window.center()
        return window
    }

    private func bringToFront() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        guide.stop()
        // Closing early is a choice to skip the optional steps, not to see them again next launch.
        if Permissions.status.permissionsGranted { completed = true }
    }

    // MARK: - Live status

    private func startPolling() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        var status = Permissions.status
        status.keyboardConnected = environment.keyboardConnected()
        if model.status != status { model.status = status }
        let enabled = environment.appEnabled()
        if model.appEnabled != enabled { model.appEnabled = enabled }
        let modes = environment.modes()
        if model.modes != modes { model.modes = modes }
    }
}

enum SetupAction {
    case next, skip, back
    case grant(Permission)
    case relaunch
    case openBluetooth
    case enableApp
    case setLaunchAtLogin(Bool)
}
