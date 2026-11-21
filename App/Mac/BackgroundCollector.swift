import AppKit
import Pairing

/// The collector mode of the app (E9-6, D-26). It uses the app's own model, so it signs with the app's device key and syncs the
/// same way the hourly timer does. It never opens a window, exits at once when the app is running, and gives up after five minutes.
@MainActor
enum BackgroundCollector {
    static let flag = "--background-collect"

    static func run() {
        let me = Bundle.main.bundleIdentifier ?? "com.ainkrad.core"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: me).filter {
            $0.processIdentifier != getpid()
        }
        // Hand-off: while the app runs it is the collector.
        if !others.isEmpty { exit(0) }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let app = AppModel()
        Task { @MainActor in
            await app.start()
            await app.collectInBackground()
            exit(0)
        }
        Task {
            try? await Task.sleep(for: .seconds(300))
            exit(0)
        }
        NSApplication.shared.run()
    }
}
