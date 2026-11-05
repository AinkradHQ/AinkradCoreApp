import Accounts
import Shell
import SwiftUI

/// What this module adds to the shell: Settings sections, launcher entries.
@MainActor
enum Registration {
    static func install(into app: AppModel) {
        let shell = app.shell
        app.admin.install()
        app.accounts.install()
        shell.settings.section(
            SettingsSection(
                id: "devices", group: .core, title: "Devices", sub: "Paired Macs, phones, runners and passkeys",
                symbol: "iphone", order: 1
            ) {
                DevicesSection(app: app)
            })
        shell.settings.section(
            SettingsSection(id: "forget", group: .core, title: "Forget this Core", symbol: "trash", order: 9) {
                ForgetSection(app: app)
            })
        shell.settings.section(
            SettingsSection(
                id: "lockouts", group: .security, title: "Lockouts", sub: "Addresses the Core has locked out",
                symbol: "lock", order: 0
            ) {
                LockoutsSection(app: app)
            })
        shell.launcher.register(
            LauncherEntry(
                id: "devices", title: "Devices", sub: "Settings, Core", symbol: "iphone",
                keywords: ["pair", "revoke", "rename", "scopes"]
            ) { openSettings(shell, "devices") })
        shell.launcher.register(
            LauncherEntry(
                id: "add-device", title: "Add device", sub: "Make a pairing code", symbol: "plus.rectangle",
                keywords: ["pair", "qr", "code", "approve"], isAction: true
            ) { app.openAddDevice() })
        shell.launcher.register(
            LauncherEntry(
                id: "lockouts", title: "Lockouts", sub: "Settings, Security", symbol: "lock",
                keywords: ["locked", "clear", "failed", "attempts"]
            ) { openSettings(shell, "lockouts") })
    }

    private static func openSettings(_ shell: ShellModel, _ id: String) {
        shell.settings.selected = id
        shell.open(.settings)
    }
}
