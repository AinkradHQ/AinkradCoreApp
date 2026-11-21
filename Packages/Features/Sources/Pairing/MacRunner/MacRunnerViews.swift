import CoreUI
import SwiftUI

/// The two switches. Used in Settings and on the setup end screen (where the second one waits until the first is on).
struct MacRunnerSwitches: View {
    let model: MacRunnerModel
    var showTerminals = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            GlassToggleTile(
                "Use this Mac as a runner", sub: "Works for your Core while you are logged in and the Mac is awake",
                symbol: "laptopcomputer",
                isOn: Binding(get: { model.useThisMac }, set: { v in Task { await model.setUseThisMac(v) } }),
                fill: true
            )
            .disabled(!model.isAvailable || model.isBusy)
            .accessibilityIdentifier("mac-runner-switch")
            if showTerminals {
                GlassToggleTile(
                    "Terminals on this Mac", sub: MacRunnerModel.terminalsWarning, symbol: "terminal",
                    isOn: Binding(get: { model.terminals }, set: { v in Task { await model.setTerminals(v) } }),
                    fill: true
                )
                .disabled(!model.isAvailable || !model.useThisMac || model.isBusy)
                .accessibilityIdentifier("mac-runner-terminals-switch")
            }
        }
    }
}

/// What the runner is doing now, and what this Mac cannot do yet.
struct MacRunnerStatus: View {
    let model: MacRunnerModel
    var accounts: String?
    var connected: Bool?
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            switch model.state {
            case .running:
                let h = MacRunnerModel.headline(connected: connected)
                CoreNotice(
                    symbol: h.done ? "checkmark" : "clock", title: h.title, text: h.text, tone: h.done ? .done : .warn)
            case .working(let what):
                HStack(spacing: Space.s2) {
                    CoreBusyBar()
                    Text(what).foregroundStyle(palette.text2)
                }
            case .needsApproval:
                CoreNotice(
                    symbol: "exclamationmark.triangle", title: "Allow Ainkrad in Login Items",
                    text: "macOS asks once, in System Settings.", tone: .warn
                ) {
                    Button("Open Login Items") { model.openLoginItems() }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            case .failed(let why):
                CoreNotice(
                    symbol: "exclamationmark.triangle", title: "This Mac is not a runner", text: why, tone: .fail)
            case .off, .unavailable:
                EmptyView()
            }
            if let problem = model.problem {
                Text(problem).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mac-runner-problem")
            }
            if model.useThisMac {
                Text(MacRunnerModel.accountsLine(accounts)).coreFont(size: MacTextSize.meta).foregroundStyle(
                    palette.text2
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        // The Core's list refreshes on its own; launchd and the runner's note are looked at when this opens and when the
        // connection changes.
        .task(id: connected) { await model.refreshProblem(connected: connected) }
    }
}
