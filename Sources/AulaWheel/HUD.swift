import AppKit
import SwiftUI

struct PickerItem: Identifiable, Equatable {
    var id: String
    var symbol: String
    var title: String
}

enum HUDContent: Equatable {
    case banner(symbol: String, title: String, subtitle: String?)
    case picker(items: [PickerItem], highlighted: Int)
}

final class HUDModel: ObservableObject {
    @Published var content: HUDContent = .banner(symbol: "dial.low", title: "", subtitle: nil)
}

/// Floating, non-activating panel that never takes focus from the app in use.
@MainActor
final class HUDController {
    var displaySeconds: TimeInterval = 1.0

    private let model = HUDModel()
    private let panel: NSPanel
    private let hosting: NSHostingView<HUDView>
    private var hideWork: DispatchWorkItem?
    private var generation = 0

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // Liquid Glass draws its own edge and shadow; the window shadow would add a second one.
        if #available(macOS 26.0, *) { panel.hasShadow = false } else { panel.hasShadow = true }
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hosting = NSHostingView(rootView: HUDView(model: model))
        panel.contentView = hosting
    }

    func showBanner(symbol: String, title: String, subtitle: String?) {
        show(.banner(symbol: symbol, title: title, subtitle: subtitle))
        scheduleHide(after: displaySeconds)
    }

    func showPicker(items: [PickerItem], highlighted: Int) {
        show(.picker(items: items, highlighted: highlighted))
        hideWork?.cancel()
    }

    func hide() {
        hideWork?.cancel()
        generation += 1
        let current = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    private func show(_ content: HUDContent) {
        generation += 1
        if case .picker = model.content, case .picker = content, panel.isVisible {
            withAnimation(.snappy(duration: 0.18)) { model.content = content }
        } else {
            model.content = content
        }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height)
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        // Replaces any running fade-out; assigning alphaValue directly would lose to the animation.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        Group {
            switch model.content {
            case .banner(let symbol, let title, let subtitle):
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 14, weight: .semibold))
                        if let subtitle {
                            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 22)
                .padding(.vertical, 10)
                .hudGlass()
            case .picker(let items, let highlighted):
                HStack(spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let selected = index == highlighted
                        HStack(spacing: 7) {
                            Image(systemName: item.symbol).font(.system(size: 14, weight: .semibold))
                            Text(item.title).font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(Capsule().fill(selected ? Color.accentColor : Color.clear))
                    }
                }
                .padding(5)
                .hudGlass()
            }
        }
        .padding(10)
        .fixedSize()
    }
}

private extension View {
    /// Liquid Glass on macOS 26+, a blurred capsule elsewhere. The compiler check keeps the
    /// project building with Xcode versions whose SDK has no `glassEffect`.
    @ViewBuilder
    func hudGlass() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            blurredCapsule()
        }
        #else
        blurredCapsule()
        #endif
    }

    func blurredCapsule() -> some View {
        background(VisualEffectBackground())
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
