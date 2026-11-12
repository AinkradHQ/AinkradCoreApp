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
            Text("This Mac can run terminals and agents for your Core, as a second machine beside the Core itself.")
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
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
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Toggle(
                "Use this Mac as a runner",
                isOn: Binding(get: { model.useThisMac }, set: { v in Task { await model.setUseThisMac(v) } })
            )
            .disabled(!model.isAvailable || model.isBusy)
            .accessibilityIdentifier("mac-runner-switch")
            if showTerminals {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Toggle(
                        "Terminals on this Mac",
                        isOn: Binding(get: { model.terminals }, set: { v in Task { await model.setTerminals(v) } })
                    )
                    .disabled(!model.isAvailable || !model.useThisMac || model.isBusy)
                    .accessibilityIdentifier("mac-runner-terminals-switch")
                    Text(MacRunnerModel.terminalsWarning).coreFont(size: MacTextSize.meta).foregroundStyle(
                        palette.text2
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
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
                    symbol: "checkmark.circle", title: "This Mac is a runner",
                    text: "It works for your Core while you are logged in and the Mac is awake.", tone: .done
                ) {}
            case .working(let what):
                HStack(spacing: Space.s2) {
                    CoreBusyBar()
                    Text(what).foregroundStyle(palette.text2)
                }
            case .needsApproval:
                CoreNotice(
                    symbol: "exclamationmark.triangle", title: "Allow Ainkrad in Login Items",
                    text: "macOS asks you to allow the runner once, in System Settings, Login Items.", tone: .warn
                ) {
                    Button("Open Login Items") { model.openLoginItems() }.coreGlassButton()
                }
            case .failed(let why):
                CoreNotice(symbol: "xmark.octagon", title: "This Mac is not a runner", text: why, tone: .fail) {}
            case .off, .unavailable:
                EmptyView()
            }
            if model.useThisMac {
                Text(
                    "When this Mac sleeps or goes offline, its terminals and agents pause. The Core keeps the session and shows it as interrupted."
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).fixedSize(
                    horizontal: false, vertical: true)
                Text(MacRunnerModel.accountsLine(accounts)).coreFont(size: MacTextSize.meta).foregroundStyle(
                    palette.text2
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
