import AppKit
import ApplicationServices
import AulaWheelCore
import IOKit.hid

enum Permission: CaseIterable {
    case accessibility, inputMonitoring

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    var isGranted: Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        }
    }

    /// Asks the system to add the app to the list. It may also show its own alert.
    func request() {
        switch self {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .inputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    func openSettings() {
        let anchor = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum Permissions {
    static var accessibility: Bool { Permission.accessibility.isGranted }
    static var inputMonitoring: Bool { Permission.inputMonitoring.isGranted }

    static var status: SetupStatus {
        SetupStatus(accessibility: accessibility, inputMonitoring: inputMonitoring)
    }

    static func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Only possible when running from an app bundle; `swift run` has nothing to reopen.
    static var canRelaunch: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Some macOS versions only apply a new grant to a fresh process.
    static func relaunch() {
        guard canRelaunch else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
