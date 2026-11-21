import CoreUI
import SwiftUI

/// Settings, Updates: everything that updates, top to bottom. The Core (its version, the latest, Update now with the three
/// steps and the result), each runner, this Mac app (Sparkle), and the automatic-update choice and hour. Keys: ⌘U updates the
/// Core, ⌥⌘U checks, ⇧⌘U updates every runner that is behind, ⌥⌘I checks or installs this app.
struct UpdatesPage: View {
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var shell: ShellModel

    private var model: UpdatesModel { shell.updates }

    /// The Core's update status, with the version "Check now" found when the status poll has not seen it yet.
    private var status: CoreUpdateStatus {
        var s = shell.coreUpdate
        if s.available == nil, !s.running, model.check?.status == .available, let v = model.check?.latest,
            v != running
        {
            s.available = v
        }
        return s
    }

    private var running: String {
        let s = shell.coreUpdate
        return s.current.isEmpty ? shell.home.health?.version ?? model.check?.current ?? "Not reported yet" : s.current
    }

    private var latest: String {
        if let v = status.available { return v }
        switch model.check?.status {
        case .upToDate: return "Up to date"
        case .available: return model.check?.latest ?? "Newer"
        case .feedUnavailable: return "Not known yet"
        case nil: return "Not checked yet"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            coreSection
            runnersSection
            appSection
            autoSection
        }
        .foregroundStyle(GlassInk.primary)
        .task { await shell.corePage.load() }
        .task { await model.watch() }
    }

    // MARK: Core

    private var coreSection: some View {
        GlassSection("Core", sub: shell.home.coreName, symbol: "server.rack", hue: GlassInk.accent(paneAccent)) {
            VStack(alignment: .leading, spacing: Space.s2) {
                fact("Running", value: running)
                fact("Latest", value: latest)
                if status.visible {
                    CoreUpdatePanel(
                        status: status, update: { shell.startCoreUpdate?() }, news: { shell.coreUpdateNews?() },
                        what: { shell.showWhatHappened() }
                    )
                    .disabled(shell.startCoreUpdate == nil)
                }
                HStack(spacing: Space.s3) {
                    if model.supported {
                        AppActionTile(
                            title: model.checking ? "Checking…" : "Check now", symbol: "arrow.clockwise", key: "⌥⌘U",
                            hue: GlassInk.slate
                        ) { Task { await model.checkNow() } }
                        .keyboardShortcut("u", modifiers: [.command, .option])
                        .disabled(model.checking || status.running)
                    }
                    Text(model.checkWords(lastChecked: shell.corePage.prefs.updateCheckedAt))
                        .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                if let why = model.failure { Text(why).foregroundStyle(GlassInk.secondary) }
            }
        }
    }

    // MARK: Runners

    private var runnersSection: some View {
        let latestRunner = model.check?.latestRunner ?? (running == "Not reported yet" ? nil : running)
        return GlassSection(
            "Runners", sub: latestRunner.map { "Latest runner version \($0)" } ?? "The machines that do the work",
            symbol: "cpu", hue: GlassInk.accent(paneAccent), index: 1
        ) {
            VStack(alignment: .leading, spacing: Space.s2) {
                if !model.supported {
                    Text("This Core is too old to update its runners from here.").foregroundStyle(GlassInk.secondary)
                } else if model.runners.isEmpty {
                    Text("No runners yet.").foregroundStyle(GlassInk.secondary)
                } else {
                    ForEach(model.runners) { r in runnerRow(r) }
                    let behind = model.behind.count
                    if behind > 0 {
                        HStack {
                            AppActionTile(
                                title: behind == 1 ? "Update it" : "Update all \(behind)",
                                symbol: "arrow.down.circle", key: "⇧⌘U", hue: GlassInk.slate
                            ) { Task { await model.updateAllBehind() } }
                            .keyboardShortcut("u", modifiers: [.command, .shift])
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private func runnerRow(_ r: UpdatableRunner) -> some View {
        let state = model.state(r)
        let version = r.version.map { "Version \($0)" } ?? "Version not reported"
        return CoreRow(
            r.name, subtitle: "\(version) · \(Self.words(state))",
            symbol: r.builtIn ? "desktopcomputer" : "server.rack",
            trailing: {
                switch state {
                case .behind:
                    AppActionTile(title: "Update", symbol: "arrow.down.circle", key: "", hue: GlassInk.slate) {
                        Task { await model.update(runner: r.id) }
                    }
                    .accessibilityLabel("Update \(r.name)")
                case .updating, .starting: StateBadge("Updating", tone: .run, symbol: "arrow.triangle.2.circlepath")
                case .upToDate: StateBadge("Up to date", tone: .done, symbol: "checkmark")
                case .offline: StateBadge("Offline", tone: .queue, symbol: "moon")
                case .withApp: StateBadge("With this app", tone: .queue, symbol: "desktopcomputer")
                }
            })
    }

    static func words(_ s: RunnerUpdateState) -> String {
        switch s {
        case .updating: "Updating now, back in a minute"
        case .starting: "Asked to update"
        case .behind: "A newer version is ready"
        case .offline: "Offline, updates when it is back"
        case .withApp: "Updates with this Mac app"
        case .upToDate: "Up to date"
        }
    }

    // MARK: This Mac app

    private var appSection: some View {
        GlassSection(
            "This Mac app", sub: "Ainkrad \(model.appVersion)", symbol: "desktopcomputer",
            hue: GlassInk.accent(paneAccent), index: 2
        ) {
            HStack(spacing: Space.s3) {
                if let ready = model.appReady {
                    AppActionTile(
                        title: "Restart to install \(ready)", symbol: "arrow.clockwise", key: "⌥⌘I",
                        hue: GlassInk.accent(paneAccent), prominent: true
                    ) { model.installApp?() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    Text("Downloaded. Or it restarts by itself when you are idle.").foregroundStyle(GlassInk.secondary)
                } else {
                    AppActionTile(
                        title: "Check for updates", symbol: "arrow.clockwise", key: "⌥⌘I", hue: GlassInk.slate
                    ) {
                        model.checkApp?()
                    }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .disabled(model.checkApp == nil)
                    Text("Updates download by themselves and install when you are idle.")
                        .foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Automatic

    /// Where an update may install: the stored hour always shows, even when it is not one of these.
    private var hours: [CoreSelectOption<Int>] {
        var list = [(3, "Night, around 3:00"), (6, "Early morning, around 6:00"), (22, "Late evening, around 22:00")]
        let now = shell.corePage.prefs.updateHour
        if !list.contains(where: { $0.0 == now }) { list.append((now, "Around \(now):00")) }
        return list.map { CoreSelectOption($0.0, $0.1) }
    }

    private var autoSection: some View {
        GlassSection(
            "Automatic updates", sub: "The app, the Core and the runners", symbol: "clock",
            hue: GlassInk.accent(paneAccent), index: 3
        ) {
            VStack(spacing: Space.s2) {
                if shell.corePage.supported {
                    CoreRow(
                        "Update by themselves", subtitle: "App, Core and runners",
                        trailing: {
                            CoreSwitch(
                                isOn: Binding(
                                    get: { shell.corePage.prefs.autoUpdate },
                                    set: { on in Task { await shell.corePage.save(autoUpdate: on) } }))
                        })
                    CoreRow(
                        "Install at", subtitle: "Core restarts for about 10 seconds",
                        trailing: {
                            CoreSelect(
                                nil,
                                selection: Binding(
                                    get: { shell.corePage.prefs.updateHour },
                                    set: { hour in Task { await shell.corePage.save(updateHour: hour) } }),
                                options: hours
                            )
                            .frame(width: Space.s8 * 5)
                        })
                } else {
                    Text("This Core is too old to keep these choices.").foregroundStyle(GlassInk.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func fact(_ title: String, value: String) -> some View {
        CoreRow(title, trailing: { Text(value).foregroundStyle(GlassInk.secondary) })
    }
}
