import CoreUI
import SwiftUI

/// Settings, Core (D-11, mockup 03-settings): Overview, Updates and Backup for everyone; Network, Storage and Logs behind
/// the one Advanced switch. Facts come from `shell.home.health` and the connection; what has no service yet says so.
extension ShellModel {
    func coreTabs() -> [SettingsTab] {
        [
            SettingsTab("overview", "Overview", order: 0) { CoreOverviewTab(shell: self) },
            SettingsTab("updates", "Updates", order: 1) { CoreUpdatesTab(shell: self) },
            SettingsTab("backup", "Backup", order: 2) { CoreBackupTab(shell: self) },
            SettingsTab("network", "Network", order: 3, advanced: true) { CoreNetworkTab(shell: self) },
            SettingsTab("storage", "Storage", order: 4, advanced: true) { CoreStorageTab(shell: self) },
            SettingsTab("logs", "Logs", order: 5, advanced: true) { CoreLogsTab(shell: self) },
        ]
    }
}

private func fact(_ title: String, _ sub: String? = nil, value: String) -> some View {
    CoreRow(title, subtitle: sub, trailing: { Text(value).foregroundStyle(GlassInk.secondary) })
}

struct CoreOverviewTab: View {
    @Bindable var shell: ShellModel
    @State private var draft = ""

    var body: some View {
        let h = shell.home.health
        VStack(alignment: .leading, spacing: Space.s4) {
            GlassSection(
                shell.home.coreName,
                sub: h.map { "Version \($0.version) · up for \($0.uptime)" } ?? "Not reported yet",
                symbol: "server.rack", hue: GlassInk.blue
            ) {
                Text(shell.chipState?.popTitle ?? "Not connected").foregroundStyle(GlassInk.secondary)
            }
            GlassSection("Basics", symbol: "slider.horizontal.3", hue: GlassInk.blue, index: 1) {
                VStack(spacing: Space.s2) {
                    nameRow
                    CoreRow(
                        "Devices", subtitle: "Who can reach this Core",
                        trailing: {
                            AppActionTile(title: "Manage", symbol: "iphone", key: "", hue: GlassInk.slate) {
                                shell.launcher.entry("devices")?.run()
                            }
                        })
                    if shell.corePage.supported {
                        CoreRow(
                            "Crash reports", subtitle: "Anonymous, never your files or notes",
                            trailing: {
                                CoreSwitch(
                                    isOn: Binding(
                                        get: { shell.corePage.prefs.crashReports },
                                        set: { on in Task { await shell.corePage.save(crashReports: on) } }))
                            })
                    }
                    if let why = shell.corePage.failure { Text(why).foregroundStyle(GlassInk.secondary) }
                }
            }
            if shell.settings.advanced {
                if let danger = shell.settings.overviewDanger {
                    GlassSection("Careful", symbol: "exclamationmark.triangle", hue: GlassInk.red, index: 2) {
                        danger()
                    }
                }
            } else {
                HStack(spacing: Space.s3) {
                    IconTile("gearshape", hue: GlassInk.slate, size: 32)
                    Text("Looking for network, storage or logs? Turn on Advanced, top right.")
                        .foregroundStyle(GlassInk.secondary)
                    Spacer(minLength: Space.s3)
                    AppActionTile(title: "Turn on", symbol: "switch.2", key: "", hue: GlassInk.slate) {
                        shell.settings.advanced = true
                    }
                }
                .padding(Space.s3)
                .coreWell()
            }
        }
        .foregroundStyle(GlassInk.primary)
        .task {
            await shell.corePage.load()
            draft = shell.corePage.prefs.name ?? shell.home.coreName
        }
    }

    /// The name is a field once this Core can keep it (Return saves); an older Core shows it as text.
    @ViewBuilder private var nameRow: some View {
        if shell.corePage.supported {
            CoreRow(
                "Name", subtitle: "How this Core shows up on your devices",
                trailing: {
                    CoreTextField(
                        "Name", placeholder: shell.home.coreName, text: $draft,
                        onSubmit: {
                            let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            Task {
                                await shell.corePage.save(name: name)
                                if let saved = shell.corePage.prefs.name {
                                    draft = saved
                                    shell.home.coreName = saved
                                }
                            }
                        }
                    )
                    .frame(width: Space.s8 * 4)
                })
        } else {
            fact("Name", "How this Core shows up on your devices", value: shell.home.coreName)
        }
    }
}

/// Update choice and hour live on the Core (Core 0.10); installing an update is E12's, so "check now" says whether a feed answered.
struct CoreUpdatesTab: View {
    @Bindable var shell: ShellModel

    /// Where an update may install: the stored hour always shows, even when it is not one of these.
    private var hours: [CoreSelectOption<Int>] {
        var list = [(3, "Night, around 3:00"), (6, "Early morning, around 6:00"), (22, "Late evening, around 22:00")]
        let now = shell.corePage.prefs.updateHour
        if !list.contains(where: { $0.0 == now }) { list.append((now, "Around \(now):00")) }
        return list.map { CoreSelectOption($0.0, $0.1) }
    }

    var body: some View {
        let h = shell.home.health
        VStack(alignment: .leading, spacing: Space.s4) {
            GlassSection(
                "Updates", sub: "Core, runners and this app", symbol: "arrow.down.circle", hue: GlassInk.blue
            ) {
                VStack(spacing: Space.s2) {
                    fact("Core version", value: h?.version ?? "Not reported yet")
                    fact("Running for", value: h?.uptime ?? "Not reported yet")
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
                    }
                }
            }
            if shell.corePage.supported {
                HStack(spacing: Space.s3) {
                    AppActionTile(
                        title: shell.corePage.checking ? "Checking…" : "Check now", symbol: "arrow.clockwise", key: "",
                        hue: GlassInk.slate
                    ) { Task { await shell.corePage.checkNow() } }
                    .disabled(shell.corePage.checking)
                    Text(checkLine).foregroundStyle(GlassInk.secondary)
                }
            }
        }
        .foregroundStyle(GlassInk.primary)
        .task { await shell.corePage.load() }
    }

    private var checkLine: String {
        if let note = shell.corePage.checkNote { return note }
        guard let at = shell.corePage.prefs.updateCheckedAt else { return "Not checked yet" }
        return "Last checked \(at.formatted(.relative(presentation: .named)))"
    }
}

/// The last backup the Core reports, and what the backup files use. The schedule, how long backups are kept and "Back up now"
/// belong to the Core machine's backup timer and its root-owned helper, which the app cannot change.
struct CoreBackupTab: View {
    @Bindable var shell: ShellModel

    var body: some View {
        let h = shell.home.health
        GlassSection("Backup", sub: "Kept safe on your Core", symbol: "externaldrive", hue: GlassInk.blue) {
            VStack(spacing: Space.s2) {
                fact("Last backup", value: h?.backup(now: Date()) ?? "Not reported yet")
                if let s = shell.corePage.storage, let n = s.backupsCount, let b = s.backups {
                    fact("Kept", value: "\(n) \(n == 1 ? "backup" : "backups"), \(Self.size(b))")
                }
                Text("Back up on a schedule, and keep them for as long as you like, on the Core machine.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .task { await shell.corePage.loadStorage() }
    }

    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

struct CoreNetworkTab: View {
    @Bindable var shell: ShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            GlassSection(
                "How you reach your Core", symbol: "network", hue: GlassInk.blue
            ) {
                VStack(spacing: Space.s2) {
                    fact("Address", "Where this app connects", value: shell.home.coreName)
                    fact("Connection", value: shell.chipState?.popTitle ?? "Not connected")
                    if let c = shell.home.health?.certificate { fact("Certificate", "Time left", value: c) }
                }
            }
            if shell.retryConnection != nil {
                HStack {
                    AppActionTile(title: "Reconnect now", symbol: "arrow.clockwise", key: "⌘R", hue: GlassInk.slate) {
                        shell.retryConnection?()
                    }
                    Spacer()
                }
            }
        }
        .foregroundStyle(GlassInk.primary)
    }
}

/// Disk use by kind of data, from the Core (needs Core 0.10); an older Core says so.
struct CoreStorageTab: View {
    @Bindable var shell: ShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            if let s = shell.corePage.storage {
                GlassSection("Space used", symbol: "internaldrive", hue: GlassInk.blue) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        if let pct = s.diskUsedPct {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(pct)%").coreFont(size: MacTextSize.large, weight: .bold)
                                if let total = s.diskTotal {
                                    Text("of \(CoreBackupTab.size(total))").foregroundStyle(GlassInk.secondary)
                                }
                            }
                            CoreMeter(Double(pct) / 100, low: pct >= 90, label: "Disk used")
                        }
                        part("Projects", s.projects, "folder")
                        part("Database, notes and Brain", s.database, "tray.full")
                        part("Backups", s.backups, "externaldrive")
                        part("Everything else", s.other, "ellipsis")
                    }
                }
            } else {
                Text(shell.corePage.supported ? "Reading the disk…" : "This Core is too old to report its storage.")
                    .foregroundStyle(GlassInk.secondary)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .task { await shell.corePage.loadStorage() }
    }

    @ViewBuilder private func part(_ title: String, _ bytes: Int64?, _ symbol: String) -> some View {
        if let bytes {
            CoreRow(
                title, symbol: symbol,
                trailing: { Text(CoreBackupTab.size(bytes)).foregroundStyle(GlassInk.secondary) })
        }
    }
}

/// The audit log is the Core's log until a plain log feed exists.
struct CoreLogsTab: View {
    @Bindable var shell: ShellModel

    var body: some View {
        GlassSection("Recent", sub: "Who did what, where and when", symbol: "doc.text", hue: GlassInk.blue) {
            HStack {
                Text("The audit log lists what happened on your Core.").foregroundStyle(GlassInk.secondary)
                Spacer(minLength: Space.s3)
                AppActionTile(title: "Open the audit log", symbol: "doc.text", key: "", hue: GlassInk.slate) {
                    shell.launcher.entry("admin-audit")?.run()  // Audit is an Activity tab now
                }
            }
        }
        .foregroundStyle(GlassInk.primary)
    }
}
