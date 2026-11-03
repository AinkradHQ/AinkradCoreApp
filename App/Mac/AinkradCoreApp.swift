import AinkradClient
import CoreUI
import SwiftUI

@main
struct AinkradCoreApp: App {
    var body: some Scene {
        WindowGroup("Ainkrad Core") {
            // E5-00 skeleton: proves the app links the vendored client. The shell replaces this in E5-03.
            Text(verbatim: "Ainkrad Core")
                .frame(minWidth: 640, minHeight: 400)
        }
        #if DEBUG
        Window("CoreUI Gallery", id: "gallery") {
            CoreUIGallery().frame(minWidth: 720, minHeight: 600)
        }
        .commands { DebugCommands() }
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
