import AinkradClient
import SwiftUI

@main
struct AinkradCoreApp: App {
    var body: some Scene {
        WindowGroup("Ainkrad Core") {
            // E5-00 skeleton: proves the app links the vendored client. The shell replaces this in E5-03.
            Text(verbatim: "Ainkrad Core")
                .frame(minWidth: 640, minHeight: 400)
        }
    }
}
