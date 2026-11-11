import AulaWheelCore
import SwiftUI

struct SetupView: View {
    @ObservedObject var model: SetupModel
    let send: (SetupAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            content
                .id(model.step)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 24)),
                    removal: .opacity))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 40)
                .padding(.top, 44)
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 560, height: 600)
        // The top padding already clears the transparent title bar.
        .ignoresSafeArea()
        .animation(.snappy(duration: 0.25), value: model.step)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome: WelcomeStep(modes: model.modes)
        case .permissions: PermissionsStep(model: model, send: send)
        case .keyboard: KeyboardStep(connected: model.status.keyboardConnected, send: send)
        case .tryIt: TryItStep(model: model, send: send)
        }
    }

    private var footer: some View {
        ZStack {
            StepIndicator(current: model.step)
            HStack(spacing: 12) {
                if model.step != .welcome {
                    Button("Back") { send(.back) }
                }
                Spacer()
                if model.canSkip && !model.canContinue {
                    Button("Skip for Now") { send(.skip) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
                Button { send(.next) } label: {
                    Text(primaryTitle).frame(minWidth: 72)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canContinue)
            }
        }
        .controlSize(.large)
    }

    private var primaryTitle: String {
        switch model.step {
        case .welcome: "Get Started"
        case .permissions, .keyboard: "Continue"
        case .tryIt: "Finish"
        }
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    let modes: [ModeConfig]

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(
                symbol: "dial.medium.fill", tint: .accentColor,
                title: "Welcome to AulaWheel",
                subtitle: "Your AULA keyboard’s volume knob, now also a scroll wheel and a media scrubber.")
            Card {
                ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                    if index > 0 { Divider().padding(.leading, 52) }
                    Row(symbol: mode.symbol, tint: .accentColor, title: mode.name, detail: Self.detail(for: mode))
                }
                Divider().padding(.leading, 52)
                Row(symbol: "hand.tap.fill", tint: .gray, title: "Double-press to switch",
                    detail: "Opens a mode picker. Turn to choose, press to pick.")
            }
            Label("Only the knob is handled. Everything else you type goes straight through, and nothing leaves your Mac.",
                  systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static func detail(for mode: ModeConfig) -> String {
        switch mode.id {
        case "volume": "Turn to change volume, press to mute."
        case "scroll": "Turn to scroll the window under the pointer, press to change speed."
        case "media": "Turn to seek in the focused player, press to play or pause."
        default: "A mode from your config file."
        }
    }
}

private struct PermissionsStep: View {
    @ObservedObject var model: SetupModel
    let send: (SetupAction) -> Void

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(
                symbol: "lock.shield.fill", tint: .blue,
                title: "Allow access",
                subtitle: "AulaWheel needs two macOS permissions to read the knob and act on it.")
            Card {
                permissionRow(.accessibility, symbol: "accessibility",
                              detail: "Catch the knob and send volume, scroll and media actions.")
                Divider().padding(.leading, 52)
                permissionRow(.inputMonitoring, symbol: "keyboard",
                              detail: "See the keyboard connect, and notice when the knob switches to RGB.")
            }
            footnote
        }
    }

    private var nextMissing: Permission? {
        Permission.allCases.first { !granted($0) }
    }

    private func granted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility: model.status.accessibility
        case .inputMonitoring: model.status.inputMonitoring
        }
    }

    private func permissionRow(_ permission: Permission, symbol: String, detail: String) -> some View {
        Row(symbol: symbol, tint: .blue, title: permission.title, detail: detail) {
            if granted(permission) {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .font(.callout.weight(.medium))
                    .transition(.scale.combined(with: .opacity))
            } else if permission == nextMissing {
                Button("Open Settings…") { send(.grant(permission)) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Open Settings…") { send(.grant(permission)) }
            }
        }
        .animation(.snappy, value: granted(permission))
    }

    @ViewBuilder
    private var footnote: some View {
        if model.status.permissionsGranted {
            Label("All set. AulaWheel can now use the knob.", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.callout)
        } else {
            VStack(spacing: 8) {
                Text("A small guide appears next to System Settings and shows you what to turn on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if model.triedGranting && Permissions.canRelaunch {
                    HStack(spacing: 4) {
                        Text("Turned it on but it still shows here?")
                        Button("Restart AulaWheel") { send(.relaunch) }
                            .buttonStyle(.link)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct KeyboardStep: View {
    let connected: Bool
    let send: (SetupAction) -> Void

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(
                symbol: "keyboard.fill", tint: .indigo,
                title: "Connect your keyboard",
                subtitle: "Pair your AULA keyboard with this Mac over Bluetooth.")
            Card {
                HStack(spacing: 12) {
                    if connected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        ProgressView().controlSize(.small).frame(width: 26)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connected ? "AULA keyboard connected" : "Looking for your AULA keyboard…")
                            .font(.body.weight(.medium))
                        Text(connected ? "You’re ready to try the knob." : "This updates as soon as it connects.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
            }
            .animation(.snappy, value: connected)

            if !connected {
                Card {
                    NumberedRow(number: 1, text: "Switch the keyboard to Bluetooth mode.")
                    Divider().padding(.leading, 52)
                    NumberedRow(number: 2, text: "Pair it in System Settings → Bluetooth.") {
                        Button("Open Bluetooth…") { send(.openBluetooth) }
                    }
                }
                Text("Tested with the AULA F75 over Bluetooth and its 2.4 GHz receiver. Another model or a cable may need its vendor and product IDs set in the config file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct TryItStep: View {
    @ObservedObject var model: SetupModel
    let send: (SetupAction) -> Void

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(
                symbol: "dial.high.fill", tint: .orange,
                title: "Try the knob",
                subtitle: "Each one ticks off as soon as AulaWheel sees it.")
            if !model.appEnabled {
                Notice(symbol: "pause.circle.fill", tint: .orange, text: "AulaWheel is paused.") {
                    Button("Turn On") { send(.enableApp) }
                }
            } else if model.knobInRGB {
                Notice(symbol: "rainbow", tint: .orange,
                       text: "The knob is controlling the lights. Long-press it to switch back.")
            }
            Card {
                ForEach(Array(KnobExercise.allCases.enumerated()), id: \.element) { index, exercise in
                    if index > 0 { Divider().padding(.leading, 52) }
                    ExerciseRow(exercise: exercise, done: model.practice.done.contains(exercise))
                }
            }
            if model.practice.isComplete {
                Label("You’ve got it. The menu bar icon shows the current mode.", systemImage: "party.popper.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Open AulaWheel at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { send(.setLaunchAtLogin($0)) }))
                    .toggleStyle(.switch)
                if let error = model.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 16)
        }
        .animation(.snappy, value: model.practice)
    }
}

private struct ExerciseRow: View {
    let exercise: KnobExercise
    let done: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                .frame(width: 28)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var title: String {
        switch exercise {
        case .rotate: "Turn the knob"
        case .press: "Press the knob"
        case .openPicker: "Double-press the knob"
        case .pickMode: "Turn, then press to pick a mode"
        }
    }

    private var detail: String {
        switch exercise {
        case .rotate: "The bar at the top of the screen shows what it did."
        case .press: "A press waits a moment in case a second one follows."
        case .openPicker: "Opens the mode picker."
        case .pickMode: "Or stop turning, and the highlighted mode is picked."
        }
    }
}

// MARK: - Building blocks

private struct StepHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: tint.opacity(0.3), radius: 6, y: 3)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator))
    }
}

private struct Row<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            accessory
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

extension Row where Accessory == EmptyView {
    init(symbol: String, tint: Color, title: String, detail: String) {
        self.init(symbol: symbol, tint: tint, title: title, detail: detail) { EmptyView() }
    }
}

private struct NumberedRow<Accessory: View>: View {
    let number: Int
    let text: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.quaternary, in: Circle())
            Text(text)
            Spacer(minLength: 12)
            accessory
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

extension NumberedRow where Accessory == EmptyView {
    init(number: Int, text: String) {
        self.init(number: number, text: text) { EmptyView() }
    }
}

private struct Notice<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let text: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.callout)
            Spacer(minLength: 8)
            accessory
        }
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension Notice where Accessory == EmptyView {
    init(symbol: String, tint: Color, text: String) {
        self.init(symbol: symbol, tint: tint, text: text) { EmptyView() }
    }
}

private struct StepIndicator: View {
    let current: SetupStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SetupStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: step == current ? 18 : 7, height: 7)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current.rawValue + 1) of \(SetupStep.allCases.count)")
    }
}
