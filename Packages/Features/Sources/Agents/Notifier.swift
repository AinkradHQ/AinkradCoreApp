import Foundation
import UserNotifications

/// What macOS lets this app do about notifications.
public enum NotificationPermission: Equatable, Sendable { case notAsked, allowed, denied }

/// A macOS notification for a new approval. A protocol so tests and the demo never touch the system.
@MainActor
public protocol ApprovalNotifier: AnyObject {
    var permission: NotificationPermission { get }
    func refresh() async
    /// Asks macOS. Called only when the person says yes in the app's own words first.
    func request() async -> NotificationPermission
    func post(id: String, title: String, body: String, session: String)
    func clear(id: String)
    /// What a click on a notification does.
    var onOpen: (@MainActor (String) -> Void)? { get set }
}

/// `UNUserNotificationCenter`. Created lazily: a process with no app bundle (a unit test) never reaches it.
@MainActor
public final class SystemNotifier: ApprovalNotifier {
    public private(set) var permission: NotificationPermission = .notAsked
    public var onOpen: (@MainActor (String) -> Void)?
    private let delegate = Delegate()
    private var center: UNUserNotificationCenter {
        let c = UNUserNotificationCenter.current()
        if c.delegate == nil { c.delegate = delegate }
        return c
    }

    public init() {
        delegate.open = { [weak self] id in Task { @MainActor in self?.onOpen?(id) } }
    }

    public func refresh() async {
        let s = await center.notificationSettings().authorizationStatus
        permission = Self.map(s)
    }

    public func request() async -> NotificationPermission {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refresh()
        return permission
    }

    public func post(id: String, title: String, body: String, session: String) {
        guard permission == .allowed else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.threadIdentifier = "approvals"
        c.userInfo = ["session": session]
        center.add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    public func clear(id: String) {
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    private static func map(_ s: UNAuthorizationStatus) -> NotificationPermission {
        switch s {
        case .notDetermined: .notAsked
        case .denied: .denied
        default: .allowed
        }
    }

    /// The app is always in front (full screen), so banners show while it is active too.
    private final class Delegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
        nonisolated(unsafe) var open: (@Sendable (String) -> Void)?
        func userNotificationCenter(
            _ center: UNUserNotificationCenter, willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions { [.banner, .sound] }
        func userNotificationCenter(
            _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
        ) async {
            if let id = response.notification.request.content.userInfo["session"] as? String { open?(id) }
        }
    }
}
