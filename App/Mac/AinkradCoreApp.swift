import AinkradClient
import AppKit
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
                .onOpenURL { app.open(url: $0) }
                #if DEBUG
            .task { await SnapshotRunner.runIfRequested(app) }
                #endif
        }
        .windowStyle(.hiddenTitleBar)
        // Native full screen needs a resizable window; the enforcer keeps it from ever leaving full screen.
        .windowResizability(.contentMinSize)
        .commands {
            ShellCommands(
                shell: shell, paneCount: shell.panes.count, focusMode: shell.focusedPane != nil,
                closedCount: shell.closedPanes.count, chipOn: shell.showActivityChip,
                coreOffline: shell.coreLink == .offline || shell.coreLink == .reconnecting,
                paneTitles: shell.panes.map { ($0.id, $0.title) })
            QuitCommands(shell: shell)
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

/// Quit asks twice, like a browser: the first ⌘Q shows "Press ⌘Q again to quit", a second one within two seconds quits.
/// Only the menu item and its key go through this; logging out or an app update still quits at once.
private struct QuitCommands: Commands {
    let shell: ShellModel
    var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button("Quit Ainkrad") { QuitGuard.press(shell) }
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}

@MainActor
enum QuitGuard {
    private static var armedAt: Date?
    static let window: TimeInterval = 2

    static func press(_ shell: ShellModel) {
        if let at = armedAt, Date().timeIntervalSince(at) < window {
            NSApp.terminate(nil)
            return
        }
        armedAt = Date()
        shell.showToast("Press ⌘Q again to quit", kind: .warn)
        Task {
            try? await Task.sleep(for: .seconds(window))
            if let at = armedAt, Date().timeIntervalSince(at) >= window {
                armedAt = nil
                if shell.toast?.message == "Press ⌘Q again to quit" { shell.toast = nil }
            }
        }
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
