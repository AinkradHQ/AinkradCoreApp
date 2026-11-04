import AinkradClient
import CoreKit
import CoreUI
import Pairing
import Shell
import SwiftUI

@main
struct AinkradCoreApp: App {
    @State private var app = AinkradCoreApp.makeApp()

    private var shell: ShellModel { app.shell }

    var body: some Scene {
        // One window, forced full screen (plan D9). `Window` is single-instance and, being first, is the one opened at launch.
        Window("Ainkrad", id: "main") {
            RootView(app: app)
                .background(FullScreenEnforcer())
                #if DEBUG
            .task { await SnapshotRunner.runIfRequested(app) }
                #endif
        }
        .windowStyle(.hiddenTitleBar)
        // Native full screen needs a resizable window; the enforcer keeps it from ever leaving full screen.
        .windowResizability(.contentMinSize)
        .commands {
            ShellCommands(shell: shell, paneCount: shell.panes.count, focusMode: shell.focusedPane != nil)
            #if DEBUG
            DemoCommands(shell: shell)
            #endif
        }
        #if DEBUG
        // Debug tool window: opened only from Debug → CoreUI Gallery (⌥⌘G), never at launch and never restored, so the app
        // always starts on its main window (a restored gallery used to open instead of it).
        if #available(macOS 15, *) {
            Window("CoreUI Gallery", id: "gallery") {
                CoreUIGallery().frame(minWidth: 720, minHeight: 600)
            }
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)
            .commands { DebugCommands() }
        }
        #endif
    }

    /// Debug switches (never in Release): `CORE_DEMO=1` shows the sample desktop with no Core, `CORE_KEYSTORE=memory` keeps keys
    /// in memory so a test can pair without touching the Keychain, `CORE_IT_SAS_FILE` is where a script reads the check code.
    @MainActor private static func makeApp() -> AppModel {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        let app = AppModel(
            keyStore: env["CORE_KEYSTORE"] == "memory" ? makeDebugKeyStore() : makeKeychainKeyStore(),
            demo: env["CORE_DEMO"] == "1", sasFile: env["CORE_IT_SAS_FILE"])
        if env["CORE_DEMO"] == "1" { SampleWorld.install(into: app.shell) }
        return app
        #else
        return AppModel()
        #endif
    }
}

#if DEBUG
private struct DebugCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandMenu("Debug") {
            Button("CoreUI Gallery") { openWindow(id: "gallery") }
                .keyboardShortcut("g", modifiers: [.option, .command])
        }
    }
}
#endif
