import CoreUI
import Shell
import SwiftUI

extension LeylineModel {
    // MARK: launcher

    public func install() {
        let shell = host.shell
        // Settings, Apps, Leyline: Look (follows Appearance unless turned off) and Options.
        shell.settings.section(
            SettingsSection(
                id: "leyline", group: .apps, title: "Leyline", sub: "Its look and what it shows",
                symbol: "point.3.connected.trianglepath.dotted", order: 7,
                tabs: [
                    SettingsTab("look", "Look", order: 0) {
                        AppLookSection(appName: "Leyline", prefs: AppLookPrefs.shared("leyline"))
                            .foregroundStyle(GlassInk.primary)
                    },
                    SettingsTab("options", "Options", order: 1) { LeylineOptionsTab() },
                ]))
        func entry(
            _ id: String, _ title: String, _ sub: String, _ symbol: String, _ keys: [String], action: Bool = false,
            _ run: @escaping @MainActor (LeylineModel) -> Void
        ) {
            shell.launcher.register(
                LauncherEntry(id: id, title: title, sub: sub, symbol: symbol, keywords: keys, isAction: action) {
                    [weak self] in if let self { run(self) }
                })
        }
        entry(
            "leyline", "Leyline", "Your hosts, their keys and how to reach them",
            "point.3.connected.trianglepath.dotted", ["ssh", "host", "server", "key", "terminal"]
        ) { $0.show() }
        entry(
            "add-host", "Add Host", "Server, sign in, name, check · asks first by default", "plus",
            ["ssh", "server", "create", "host"], action: true
        ) { $0.newHost() }
        entry(
            "add-host-advanced", "Add Host (advanced)…", "Key, jump hosts, group and tags, AI rule",
            "slider.horizontal.3",
            ["ssh", "server", "create", "host", "jump"], action: true
        ) {
            $0.show()
            $0.keysOpen = false
            HostDialogs.openAdd($0, login: "")
        }
        entry(
            "generate-key", "Generate Key", "A new SSH key, sealed in the Core · needs Touch ID", "key",
            ["ssh", "keypair", "create"], action: true
        ) {
            $0.show()
            $0.openKeyForm(.generate)
        }
    }
}
