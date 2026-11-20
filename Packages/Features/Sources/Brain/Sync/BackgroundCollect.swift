import Foundation
import ServiceManagement

/// E9-6 (D-26): the Mac collectors keep running after the window is closed and after the app is quit. The collectors sign with
/// the app's device key, so the helper is the app's own executable in collector mode (`App/Mac/BackgroundCollector.swift`),
/// started by the `com.ainkrad.core.collector` login agent every hour. While the app runs it exits and the app syncs.
public enum BackgroundCollect {
    /// Registers the app as a login item, once. Returns whether it is registered now.
    @discardableResult
    public static func ensure(_ service: SMAppService = .agent(plistName: "com.ainkrad.core.collector.plist")) -> Bool {
        switch service.status {
        case .enabled, .requiresApproval: return true
        default: break
        }
        do {
            try service.register()
            return true
        } catch {
            return false
        }
    }
}
