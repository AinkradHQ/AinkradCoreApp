import Foundation

/// How far one line of the sign-in checklist has got.
enum ConnCheck: Equatable, Sendable { case done, current, todo }

/// One line of the Sign in step's checklist.
struct ConnSignInItem: Equatable, Sendable {
    enum Role: Equatable, Sendable { case copy, open, pick, approve }
    let role: Role
    var title: String
    var detail: String?
    var state: ConnCheck
}

/// The checklist of the Sign in step, read from what the app really knows: whether the Core handed out a code, whether the
/// person pressed Copy, where the flow stands. Nothing ticks on a timer. The approval itself happens on the service's page,
/// so a line is only done when the flow says connected (or, for Jira, that it now needs a site picked).
enum ConnSignIn {
    static func items(kind: ConnKind?, flow: ConnFlow?, copied: Bool) -> [ConnSignInItem] {
        let name = kind?.name ?? "the service"
        let connected = flow?.isConnected == true
        var picking = false
        var waiting = flow == nil
        switch flow?.step {
        case .pickSite?: picking = true
        case .waiting?: waiting = true
        default: break
        }
        let approve = ConnSignInItem(
            role: .approve, title: "Approve Ainkrad",
            detail: connected ? "Approved" : waiting ? "Waiting for \(name)…" : "\(name) asks once",
            state: connected ? .done : .todo)
        if flow?.userCode != nil {
            let page = flow.map { pageName($0.url) }
            return [
                .init(role: .copy, title: "Copy this code", detail: nil, state: connected || copied ? .done : .current),
                .init(
                    role: .open, title: "Paste it on the \(name) page we opened", detail: page,
                    state: connected ? .done : copied ? .current : .todo),
                approve,
            ]
        }
        let site = ConnLook.site(kind?.id ?? "", name: name)
        return [
            .init(
                role: .open, title: "Sign in to \(site)", detail: "We opened it in your browser",
                state: connected || picking ? .done : .current),
            .init(
                role: .pick, title: "Pick your \(ConnLook.pickWord(kind?.id ?? ""))", detail: nil,
                state: connected ? .done : picking ? .current : .todo),
            approve,
        ]
    }

    /// "github.com/login/device": the address without its scheme, so it fits a line.
    static func pageName(_ url: URL) -> String {
        (url.host ?? "") + (url.path == "/" ? "" : url.path)
    }
}
