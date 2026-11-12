import CoreUI
import SwiftUI

/// A service type Core can sign in to (GitHub, Jira). The add sheet is drawn from this, so a new kind needs no new screen.
struct ConnKind: Identifiable, Equatable, Sendable {
    enum SignIn: String, Sendable {
        case deviceCode = "device_code"
        case browser
    }
    let id: String
    let name: String
    let say: String
    let signIn: SignIn
    /// The word for what limits apply to: "repositories", "projects".
    let resource: String
    /// What may be allowed, in order; the first is on by default.
    let capabilities: [ConnCapability]
    /// The Advanced sheet's token help, one step per line, and the extra fields it asks for.
    let tokenTitle: String
    let tokenHelp: [String]
    let tokenFields: [String]
    var available = true
    /// The key of the resource limit a grant carries (`repos`, `projects`); nil when the kind has none.
    var limitKey: String?
    /// Where the person installs the kind's app to choose resources (GitHub App), when the Core has it set up.
    var installURL: URL?
}

struct ConnCapability: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let say: String
    /// A write: turning it on warns and needs Touch ID.
    let writes: Bool
}

enum ConnStatus: String, Sendable {
    case connected
    case needsLook = "needs_attention"
    case disabled
}

struct ConnItem: Identifiable, Equatable, Sendable {
    let id: Int64
    let kind: String
    var name: String
    /// Whose sign-in it is: a GitHub login, a Jira site.
    let identity: String
    var status: ConnStatus
    /// Why it needs a look, in words from the Core.
    var reason: String?
    var isDefault: Bool
    var allowed: Set<String>
    /// nil: every repository or project.
    var only: [String]?
    var lastUsed: Date?
    var lastChecked: Date?
    var users: Int
}

/// Where a sign-in stands, read from the Core while the sheet is open.
struct ConnFlow: Equatable, Sendable {
    enum Step: Equatable, Sendable {
        case waiting
        /// GitHub: signed in, now choose repositories on GitHub (or skip).
        /// `install` is GitHub's page for the Ainkrad app, where the person picks repositories.
        case chooseResources(login: String, install: URL)
        /// Jira: approved, now pick a site.
        case pickSite([String])
        case connected(Int64)
        case failed(title: String, fix: String)
    }
    let id: String
    let kind: String
    /// GitHub's device code, shown big; nil for a browser sign-in.
    let userCode: String?
    let url: URL
    var step: Step
    /// The `state` an OAuth redirect must carry back with its code (not the flow id); nil for a device-code sign-in.
    var callbackState: String?
    /// The sign-in failed because connections are off on the Core: the sheet offers "Turn on connections".
    var gated = false
    var isConnected: Bool {
        if case .connected = step { return true }
        return false
    }
}

struct ConnActivity: Identifiable, Equatable, Sendable {
    let id: Int64
    let connection: Int64
    let who: String
    let what: String
    let ok: Bool
    let result: String
    let at: Date
}

/// Ainkrad's OAuth app for a kind, as the Core says it. A secret field only ever says whether it is set.
struct ConnApp: Equatable, Sendable {
    struct Field: Identifiable, Equatable, Sendable {
        /// The Core's key for the field, shown only as hover help.
        let id: String
        let title: String
        let secret: Bool
        let isSet: Bool
        /// A field that is no secret says its value.
        let value: String?
    }
    let kind: String
    let configured: Bool
    let fields: [Field]
    /// Atlassian: the address to register with them, exactly.
    let redirect: String?
}

/// What the App registration sheet shows while it reads the Core.
enum ConnAppLoad: Equatable, Sendable {
    case loading
    case ready(ConnApp)
    /// Only an admin may read or change it.
    case readOnly
    case failed(String)
}

enum ConnFilter: String, CaseIterable {
    case all = "All"
    case needsLook = "Needs a look"
    case off = "Turned off"
    func matches(_ c: ConnItem) -> Bool {
        switch self {
        case .all: true
        case .needsLook: c.status == .needsLook
        case .off: c.status == .disabled
        }
    }
}

enum ConnLook {
    static func symbol(_ kind: String) -> String {
        switch kind {
        case "github": "arrow.triangle.branch"
        case "jira": "square.stack.3d.up"
        case "linear": "line.diagonal"
        case "slack": "number"
        default: "link"
        }
    }
    static func hue(_ kind: String) -> Color {
        switch kind {
        case "github": GlassInk.slate
        case "jira": GlassInk.blue
        case "linear", "slack": GlassInk.blue
        default: GlassInk.blue
        }
    }
    static func badge(_ s: ConnStatus) -> (String, Tone, String) {
        switch s {
        case .connected: ("Connected", .done, "checkmark.circle")
        case .needsLook: ("Needs a look", .warn, "exclamationmark.triangle")
        case .disabled: ("Turned off", .queue, "pause.circle")
        }
    }
}

/// The tile of a kind: a rounded square in its colour.
struct ConnTile: View {
    let kind: String
    var large = false
    var body: some View {
        let hue = ConnLook.hue(kind)
        let size: CGFloat = large ? 48 : 34
        Image(systemName: ConnLook.symbol(kind)).coreFont(size: large ? 20 : 15, weight: .semibold)
            .foregroundStyle(.white).frame(width: size, height: size)
            .background(
                LinearGradient(colors: [hue, hue.opacity(0.55)], startPoint: .top, endPoint: .bottom),
                in: coreShape(large ? 12 : 8)
            )
            .overlay { coreShape(large ? 12 : 8).strokeBorder(.white.opacity(0.25), lineWidth: 1) }
            .accessibilityHidden(true)
    }
}
