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
                id: "privacy", group: .general, title: "Privacy", sub: "What Ainkrad may send to its own server",
                symbol: "hand.raised", order: 5
            ) {
                GlassSection(
                    "Crash reports", sub: "On by default. You can turn it off any time.", symbol: "ladybug",
                    hue: GlassInk.blue
                ) { CrashReportsSwitch() }
                .foregroundStyle(GlassInk.primary)
            })
        shell.settings.section(
            SettingsSection(
                id: "lockouts", group: .core, title: "Lockouts", sub: "Addresses the Core has locked out",
                symbol: "lock", order: 6, advancedOnly: true
            ) {
                LockoutsSection(app: app)
            })
        // About (which Core, what this device may do) moved here from Devices & Runners.
        shell.settings.tab("core", SettingsTab("about", "About", order: 1) { CoreAboutTab(app: app) })
        // One door for computers and phones (Machines): plain at once, advanced with a name and scopes.
        shell.launcher.register(
            LauncherEntry(
                id: "add-machine", title: "Add machine", sub: "This Mac, a server or another Mac, a phone · ⌘N",
                symbol: "plus.rectangle", keywords: ["add", "device", "runner", "pair", "qr", "phone", "server"],
                isAction: true
            ) { [weak app] in app?.openAddMachine() })
        shell.launcher.register(
            LauncherEntry(
                id: "add-machine-advanced", title: "Add machine (advanced)…",
                sub: "A phone or Mac that signs in: name it and choose what it may do", symbol: "slider.horizontal.3",
                keywords: ["pair", "qr", "code", "scopes", "device"], isAction: true
            ) { [weak app] in app?.openAddDevice() })
        shell.launcher.aliases["add-device"] = "add-machine"
        shell.launcher.aliases["add-device-advanced"] = "add-machine-advanced"
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
