import CoreUI
import Shell
import SwiftUI

/// "Do work on this Mac" (Machines): the Mac-runner switch and its two options, on This Mac's own page in Machines. While it
/// is off, This Mac is a sign-in-only row and this sits on that row's page; once on, it is the first row of Does work.
struct ThisMacWork: View {
    let app: AppModel
    @Environment(\.corePalette) private var palette

    private var model: MacRunnerModel { app.macRunner }
    private var connected: Bool? { model.deviceID.flatMap { app.terminals?.isOnline(runner: $0) } }

    private var statusLine: String {
        if !model.useThisMac { return "Off. Your Core sends no work to this Mac. Only while you are signed in." }
        return connected == true
            ? "On. AI sessions and terminals can run here while you are signed in and the Mac is awake."
            : "Starting. Your Core has not heard from it yet."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s3) {
                row("Do work on this Mac", statusLine, isOn: model.useThisMac, id: "mac-runner-switch") { v in
                    Task { await model.setUseThisMac(v) }
                }
                .disabled(!model.isAvailable || model.isBusy)
                if model.useThisMac {
                    row("Terminals on this Mac", MacRunnerModel.terminalsWarning, isOn: model.terminals, id: nil) { v in
                        Task { await model.setTerminals(v) }
                    }
                    .disabled(!model.isAvailable || model.isBusy)
                    row(
                        "Keep this Mac awake while working", "Only while a task is running.", isOn: model.keepAwake,
                        id: nil
                    ) {
                        model.setKeepAwake($0)
                    }
                }
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
            MacRunnerStatus(
                model: model, accounts: model.deviceID.flatMap { app.terminals?.accountsAnswer(forRunner: $0) },
                connected: connected)
            if model.useThisMac {
                HStack(spacing: Space.s2) {
                    Button {
                        model.showLog()
                    } label: {
                        Label("Show what it did", systemImage: "doc.text")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(!model.isAvailable)
                    .help("Open the runner's log in Console")
                    Button {
                        Task { await model.restart() }
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .disabled(!model.isAvailable || model.isBusy)
                    .help("Restart the work on this Mac. Running work stops")
                }
            }
        }
        .accessibilityIdentifier("this-mac-work")
    }

    private func row(
        _ title: String, _ sub: String, isOn: Bool, id: String?, set: @escaping @Sendable @MainActor (Bool) -> Void
    ) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold)
                Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            CoreSwitch("", isOn: Binding(get: { isOn }, set: set)).accessibilityLabel(title)
                .accessibilityIdentifier(id ?? title)
        }
    }
}

/// Settings, Core, About: the Core's version, what it runs on and what this device may do on it (moved from Devices &
/// Runners). Machines' versions live on each machine's page; updates are Settings, Updates.
struct CoreAboutTab: View {
    let app: AppModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s3) {
                row("Core address", app.shell.home.coreName)
                row("Version", app.about.about?.server ?? "Not reported yet")
                row("Running for", app.shell.home.health?.uptime ?? "Not reported yet")
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
            AboutBlock(app: app)
        }
        .foregroundStyle(GlassInk.primary)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(title).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).frame(
                width: Space.s8 * 5, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
