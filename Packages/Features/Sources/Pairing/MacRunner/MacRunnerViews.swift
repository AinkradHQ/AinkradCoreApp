import CoreUI
import SwiftUI

/// Settings, Mac: "Use this Mac as a runner", its state, and the terminals switch with its warning (N16, D1, D2, D3).
struct MacRunnerSection: View {
    let model: MacRunnerModel
    /// "Yes" or "No (reason)" from the runner's own report; nil when the Core has not said.
    var accounts: String?
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Run terminals and AI sessions for your Core on this Mac.").foregroundStyle(palette.text2)
            MacRunnerSwitches(model: model)
            if model.isAvailable { MacRunnerStatus(model: model, accounts: accounts) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            switch model.state {
            case .running:
                CoreNotice(
                    symbol: "checkmark", title: "This Mac is a runner",
                    text: "Its terminals and AI sessions pause while the Mac sleeps.", tone: .done)
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
            if model.useThisMac {
                Text(MacRunnerModel.accountsLine(accounts)).coreFont(size: MacTextSize.meta).foregroundStyle(
                    palette.text2
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
