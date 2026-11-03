import AinkradClient
import CoreUI
import Shell
import SwiftUI

@main
struct AinkradCoreApp: App {
    @State private var shell = AinkradCoreApp.makeShell()

    var body: some Scene {
        // One window, forced full screen (plan D9). `Window` is single-instance and, being first, is the one opened at launch.
        Window("Ainkrad Core", id: "main") {
            ShellView(shell: shell)
                .background(FullScreenEnforcer())
                #if DEBUG
            .task { await SnapshotRunner.runIfRequested(shell) }
                #endif
        }
        .windowStyle(.hiddenTitleBar)
        // Native full screen needs a resizable window; the enforcer keeps it from ever leaving full screen.
        .windowResizability(.contentMinSize)
        .commands {
            ShellCommands(shell: shell)
            #if DEBUG
            DemoCommands(shell: shell)
            #endif
        }
        #if DEBUG
        Window("CoreUI Gallery", id: "gallery") {
            CoreUIGallery().frame(minWidth: 720, minHeight: 600)
        }
        .commands { DebugCommands() }
        #endif
    }

    @MainActor private static func makeShell() -> ShellModel {
        let shell = ShellModel()
        #if DEBUG
        SampleWorld.install(into: shell)
        #endif
        return shell
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
