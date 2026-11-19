import Accounts
import Brain
import CoreUI
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
        // Forget this Core is the danger row of the Core Overview, shown while Advanced is on.
        shell.settings.overviewDanger = { AnyView(ForgetSection(app: app)) }
        shell.settings.section(
            SettingsSection(
                id: "lockouts", group: .core, title: "Lockouts", sub: "Addresses the Core has locked out",
                symbol: "lock", order: 6, advancedOnly: true
            ) {
                LockoutsSection(app: app)
            })
        shell.settings.section(
            SettingsSection(
                id: "runners", group: .apps, title: "Runners", sub: "Its look and how runners are kept up to date",
                symbol: "server.rack", order: 3,
                tabs: [
                    SettingsTab("look", "Look", order: 0) {
                        AppLookSection(appName: "Runners", prefs: AppLookPrefs.shared("runners"))
                            .foregroundStyle(GlassInk.primary)
                    },
                    SettingsTab("options", "Options", order: 1) { RunnersOptionsTab(app: app) },
                ]))
        shell.launcher.register(
            LauncherEntry(
                id: "devices-runners", title: "Devices & Runners", sub: "Devices, runners, this Mac, about",
                symbol: "iphone.and.arrow.forward", keywords: ["pair", "revoke", "rename", "scopes", "runner", "about"]
            ) { [weak app] in app?.openHub(.devices) })
        shell.launcher.register(
            LauncherEntry(
                id: "devices", title: "Devices", sub: "Devices & Runners", symbol: "iphone",
                keywords: ["pair", "revoke", "rename", "scopes"]
            ) { [weak app] in app?.openHub(.devices) })
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
