import Accounts
import Brain
import Design
import Leyline
import Lore
import Projects
import Shell
import SwiftUI

/// What this module adds to the shell: Settings sections, launcher entries.
@MainActor
enum Registration {
    static func install(into app: AppModel) {
        let shell = app.shell
        app.admin.install()
        app.accounts.install()
        app.brain.install()
        app.projects.install()
        app.leyline.install()
        app.design.install()
        app.lore.install()
        shell.settings.section(
            SettingsSection(
                id: "devices", group: .core, title: "Devices",
                sub: "This Core, and the Macs, phones, runners and passkeys that reach it",
                symbol: "iphone", order: 1
            ) {
                DevicesSection(app: app)
            })
        shell.settings.section(
            SettingsSection(
                id: "mac-runner", group: .core, title: "This Mac as a runner",
                sub: "Terminals and AI sessions that run on this Mac for your Core", symbol: "laptopcomputer", order: 7
            ) {
                MacRunnerSection(
                    model: app.macRunner,
                    accounts: app.macRunner.deviceID.flatMap { app.terminals?.accountsAnswer(forRunner: $0) },
                    connected: app.macRunner.deviceID.flatMap { app.terminals?.isOnline(runner: $0) })
            })
        // Forget this Core is the danger row of the Core Overview, shown while Advanced is on.
        shell.settings.overviewDanger = { AnyView(ForgetSection(app: app)) }
        shell.settings.section(
            SettingsSection(
                id: "lockouts", group: .core, title: "Lockouts", sub: "Addresses the Core has locked out",
                symbol: "lock", order: 6, advancedOnly: true
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
                id: "add-device", title: "Add device", sub: "A device or a runner, step by step · needs Touch ID",
                symbol: "plus.rectangle", keywords: ["pair", "qr", "code", "approve"], isAction: true
            ) { app.openAddWizard() })
        shell.launcher.register(
            LauncherEntry(
                id: "add-device-advanced", title: "Add device (advanced)…",
                sub: "Name it and choose what it may do", symbol: "slider.horizontal.3",
                keywords: ["pair", "qr", "code", "scopes", "runner"], isAction: true
            ) { app.openAddDevice() })
        shell.launcher.register(
            LauncherEntry(
                id: "lockouts", title: "Lockouts", sub: "Settings, Core", symbol: "lock",
                keywords: ["locked", "clear", "failed", "attempts"]
            ) { openSettings(shell, "lockouts") })
    }

    private static func openSettings(_ shell: ShellModel, _ id: String) {
        shell.settings.selected = id
        shell.open(.settings)
    }
}
