import AppKit
import SwiftUI

/// A small panel that sits beside the System Settings window while the user grants a permission.
///
/// It is non-activating, so dragging the app icon from it or clicking it never pulls focus away
/// from System Settings. It only shows while System Settings is frontmost.
@MainActor
final class SettingsGuide {
    /// Called once when the guided permission turns on.
    var onGranted: (() -> Void)?

    private let model = SettingsGuideModel()
    private let panel: NSPanel
    private let hosting: NSHostingView<SettingsGuideView>
    private var timer: Timer?
    private var permission: Permission?
    private static let settingsBundleID = "com.apple.systempreferences"
    private static let gap: CGFloat = 12

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hosting = NSHostingView(rootView: SettingsGuideView(model: model))
        panel.contentView = hosting
    }

    func start(_ permission: Permission) {
        self.permission = permission
        model.permission = permission
        model.granted = false
        permission.request()
        permission.openSettings()
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        permission = nil
        panel.orderOut(nil)
    }

    private func update() {
        guard let permission else { return }
        if !model.granted && permission.isGranted {
            model.granted = true
            timer?.invalidate()
            timer = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.permission == permission else { return }
                    self.stop()
                    self.onGranted?()
                }
            }
            return
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.settingsBundleID,
              let settingsFrame = Self.settingsWindowFrame()
        else {
            panel.orderOut(nil)
            return
        }
        place(beside: settingsFrame)
        panel.orderFrontRegardless()
    }

    private func place(beside window: NSRect) {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(window) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? window
        let top = min(window.maxY, visible.maxY) - size.height
        let y = max(visible.minY, top)

        let origin: NSPoint
        let edge: SettingsGuideModel.Edge
        if window.maxX + Self.gap + size.width <= visible.maxX {
            origin = NSPoint(x: window.maxX + Self.gap, y: y)
            edge = .leading
        } else if window.minX - Self.gap - size.width >= visible.minX {
            origin = NSPoint(x: window.minX - Self.gap - size.width, y: y)
            edge = .trailing
        } else {
            // No room beside it: overlap the window's bottom-right corner, clear of its sidebar.
            origin = NSPoint(x: window.maxX - size.width - Self.gap, y: window.minY + Self.gap)
            edge = .none
        }
        if model.arrowEdge != edge { model.arrowEdge = edge }
        let frame = NSRect(origin: origin, size: size)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// The frontmost System Settings window, in Cocoa screen coordinates.
    /// Window bounds of other apps are readable without Screen Recording; titles are not needed.
    private static func settingsWindowFrame() -> NSRect? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: settingsBundleID)
                .first?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }
        // The list is ordered front to back, so the first normal-level window is the one in use.
        guard let info = list.first(where: {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }),
            let bounds = info[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: bounds),
            let primary = NSScreen.screens.first
        else { return nil }
        return NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

final class SettingsGuideModel: ObservableObject {
    enum Edge { case leading, trailing, none }

    @Published var permission: Permission = .accessibility
    @Published var granted = false
    @Published var arrowEdge: Edge = .leading
}

struct SettingsGuideView: View {
    @ObservedObject var model: SettingsGuideModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if model.arrowEdge == .leading { arrow("arrow.left") }
            VStack(alignment: .leading, spacing: 12) {
                if model.granted {
                    Label("\(model.permission.title) is on", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("Taking you back to AulaWheel…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    instructions
                }
            }
            if model.arrowEdge == .trailing { arrow("arrow.right") }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))
        .animation(.snappy, value: model.granted)
    }

    @ViewBuilder
    private var instructions: some View {
        Text("Turn on AulaWheel")
            .font(.headline)
        Text("In **\(model.permission.title)**, switch on **AulaWheel**. macOS may ask for your password.")
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 10) {
            AppIconDragSource()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Not in the list?").font(.callout.weight(.medium))
                Text("Drag this icon into it.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        Text("Already on but not working? Select AulaWheel, click −, then drag the icon in again.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Waiting for permission…").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func arrow(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.top, 1)
    }
}

/// The app's own icon, draggable as a file so it can be dropped into a System Settings list.
private struct AppIconDragSource: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView, NSDraggingSource {
        private let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)

        override var intrinsicContentSize: NSSize { NSSize(width: 40, height: 40) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            icon.draw(in: bounds)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDragged(with event: NSEvent) {
            let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
            item.setDraggingFrame(bounds, contents: icon)
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
            -> NSDragOperation
        {
            context == .outsideApplication ? [.copy, .link, .generic] : []
        }
    }
}
