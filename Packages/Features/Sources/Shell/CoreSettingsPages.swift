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
            SettingsTab("storage", "Storage", order: 4, advanced: true) { CoreStorageTab() },
            SettingsTab("logs", "Logs", order: 5, advanced: true) { CoreLogsTab(shell: self) },
        ]
    }
}

private func fact(_ title: String, _ sub: String? = nil, value: String) -> some View {
    CoreRow(title, subtitle: sub, trailing: { Text(value).foregroundStyle(GlassInk.secondary) })
}

struct CoreOverviewTab: View {
    @Bindable var shell: ShellModel

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
                    fact("Name", "How this Core shows up on your devices", value: shell.home.coreName)
                    CoreRow(
                        "Devices", subtitle: "Who can reach this Core",
                        trailing: {
                            AppActionTile(title: "Manage", symbol: "iphone", key: "", hue: GlassInk.slate) {
                                shell.launcher.entry("devices")?.run()
                            }
                        })
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
    }
}

/// ponytail: no update service in the app yet (in-app update is E12); shows the version the Core reports.
struct CoreUpdatesTab: View {
    @Bindable var shell: ShellModel

    var body: some View {
        let h = shell.home.health
        GlassSection(
            "Updates", sub: "Core, runners and this app", symbol: "arrow.down.circle", hue: GlassInk.blue
        ) {
            VStack(spacing: Space.s2) {
                fact("Core version", value: h?.version ?? "Not reported yet")
                fact("Running for", value: h?.uptime ?? "Not reported yet")
                fact("Updating", "Updates by themselves arrive in a later release.", value: "Not yet")
            }
        }
        .foregroundStyle(GlassInk.primary)
    }
}

/// ponytail: shows the last backup the Core reports; "Back up now" and the schedule wait for a backup service.
struct CoreBackupTab: View {
    @Bindable var shell: ShellModel

    var body: some View {
        let h = shell.home.health
        GlassSection("Backup", sub: "Kept safe on your Core", symbol: "externaldrive", hue: GlassInk.blue) {
            VStack(spacing: Space.s2) {
                fact("Last backup", value: h?.backup(now: Date()) ?? "Not reported yet")
                fact("Back up every", "Choosing how often arrives in a later release.", value: "Day")
            }
        }
        .foregroundStyle(GlassInk.primary)
    }
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

/// ponytail: the Core reports no disk figures to the app yet.
struct CoreStorageTab: View {
    var body: some View {
        GlassSection("Space used", symbol: "internaldrive", hue: GlassInk.blue) {
            Text("How much space projects, Brain and backups use arrives when the Core reports it.")
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(GlassInk.primary)
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
                    shell.settings.selected = "audit"
                }
            }
        }
        .foregroundStyle(GlassInk.primary)
    }
}
