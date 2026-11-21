import CoreUI
import SwiftUI

/// Settings, Core (D-11, mockup 03-settings): Overview and Backup for everyone (updates are Settings, Updates); Network, Storage and Logs behind
/// the one Advanced switch. Facts come from `shell.home.health` and the connection; what has no service yet says so.
extension ShellModel {
    func coreTabs() -> [SettingsTab] {
        [
            SettingsTab("overview", "Overview", order: 0) { CoreOverviewTab(shell: self) },
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
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var shell: ShellModel
    @State private var draft = ""

    var body: some View {
        let h = shell.home.health
        VStack(alignment: .leading, spacing: Space.s4) {
            GlassSection(
                shell.home.coreName,
                sub: h.map { "Version \($0.version) · up for \($0.uptime)" } ?? "Not reported yet",
                symbol: "server.rack", hue: GlassInk.accent(paneAccent)
            ) {
                Text(shell.chipState?.popTitle ?? "Not connected").foregroundStyle(GlassInk.secondary)
            }
            GlassSection("Basics", symbol: "slider.horizontal.3", hue: GlassInk.accent(paneAccent), index: 1) {
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

/// The last backup, when they run and what is kept, and "Back up now". The schedule and the backups come from the Core machine's
/// root-owned helper (Core 0.10); the app reads them and can start one, but cannot change the timer.
struct CoreBackupTab: View {
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var shell: ShellModel

    var body: some View {
        let h = shell.home.health
        let b = shell.corePage.backups
        GlassSection("Backup", sub: "Kept safe on your Core", symbol: "externaldrive", hue: GlassInk.accent(paneAccent))
        {
            VStack(spacing: Space.s2) {
                fact("Last backup", value: h?.backup(now: Date()) ?? "Not reported yet")
                if let words = b?.scheduleWords { fact("Runs", "On the Core machine", value: words) }
                if let next = b?.nextAt, b?.available == true {
                    fact(
                        "Next backup",
                        value: next.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))
                }
                if let s = shell.corePage.storage, let n = s.backupsCount, let bytes = s.backups {
                    fact("Kept", value: "\(n) \(n == 1 ? "backup" : "backups"), \(Self.size(bytes))")
                } else if let n = b?.history.count, n > 0 {
                    fact("Kept", value: "\(n) \(n == 1 ? "backup" : "backups")")
                }
                if let r = shell.corePage.retention, let keep = r.keep, b?.available == true {
                    CoreRow(
                        "Keep backups for", subtitle: "Older ones are removed after each backup",
                        trailing: {
                            CoreSelect(
                                nil,
                                selection: Binding(
                                    get: { keep }, set: { n in Task { await shell.corePage.setKeep(n) } }),
                                options: Self.keepOptions(now: keep, range: r.min...r.max)
                            )
                            .frame(width: Space.s8 * 5)
                        })
                }
                if b?.available == true {
                    HStack(spacing: Space.s3) {
                        AppActionTile(
                            title: shell.corePage.backupStarting || b?.running == true ? "Backing up…" : "Back up now",
                            symbol: "externaldrive.badge.timemachine", key: "", hue: GlassInk.slate
                        ) { Task { await shell.corePage.backupNow() } }
                        .disabled(shell.corePage.backupStarting || b?.running == true)
                        if let note = shell.corePage.backupNote { Text(note).foregroundStyle(GlassInk.secondary) }
                        Spacer(minLength: 0)
                    }
                } else if shell.corePage.supported {
                    Text(
                        b == nil
                            ? "Reading the backup schedule…"
                            : "Backups are set up on the Core machine itself, so this app can only read them."
                    )
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("This Core is too old to show or start backups.").foregroundStyle(GlassInk.secondary)
                }
                if let why = shell.corePage.failure { Text(why).foregroundStyle(GlassInk.secondary) }
            }
        }
        .foregroundStyle(GlassInk.primary)
        .task {
            await shell.corePage.loadStorage()
            await shell.corePage.loadBackups()
        }
    }

    /// "Last 7 backups" and a few more steps inside the range the Core accepts; today's value is always one of them.
    static func keepOptions(now: Int, range: ClosedRange<Int>) -> [CoreSelectOption<Int>] {
        let counts = Set([3, 7, 14, 30, 60].filter(range.contains) + [now]).sorted()
        return counts.map { CoreSelectOption($0, "Last \($0) \($0 == 1 ? "backup" : "backups")") }
    }

    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

struct CoreNetworkTab: View {
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var shell: ShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            GlassSection(
                "How you reach your Core", symbol: "network", hue: GlassInk.accent(paneAccent)
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
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var shell: ShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            if let s = shell.corePage.storage {
                GlassSection("Space used", symbol: "internaldrive", hue: GlassInk.accent(paneAccent)) {
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
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var shell: ShellModel

    var body: some View {
        GlassSection(
            "Recent", sub: "Who did what, where and when", symbol: "doc.text", hue: GlassInk.accent(paneAccent)
        ) {
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
