import Foundation
import ServiceManagement

/// E9-6 (D-26): the Mac collectors keep running after the window is closed. The collectors run in this app (they sign with its
/// device key), so the app has to stay alive: it starts at login and closing its window no longer quits it (the app delegate).
/// ponytail: the app is the collector host; a separate signed helper would also survive a Quit, add it when that matters.
public enum BackgroundCollect {
    /// Registers the app as a login item, once. Returns whether it is registered now.
    @discardableResult
    public static func ensure(_ service: SMAppService = .mainApp) -> Bool {
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
