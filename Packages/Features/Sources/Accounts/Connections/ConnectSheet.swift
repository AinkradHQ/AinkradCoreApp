import CoreUI
import Shell
import SwiftUI

@MainActor
enum ConnDialogs {
    private static func present<V: View>(
        _ m: ConnectionsModel, _ id: String, onClose: @escaping @MainActor () -> Void = {},
        @ViewBuilder _ v: @escaping (@escaping () -> Void) -> V
    ) {
        m.host.clearElevationNotice()
        let shell = m.host.shell
        shell.present(
            ShellDialog(
                id: id,
                onClose: { [weak m] in
                    m?.host.clearElevationNotice()
                    onClose()
                }
            ) { v { shell.closeDialog() } })
    }

    /// The guided Add (D-21), or "What AI may do…" and "Choose repositories…" on a connection: `ConnAddView`.
    static func openAdd(_ m: ConnectionsModel) {
        present(m, "connection-connect", onClose: { [weak m] in m?.closeAdd() }) { close in
            ConnAddView(model: m, close: close)
        }
    }
    static func openApp(_ m: ConnectionsModel, _ k: ConnKind) {
        present(m, "connection-app") { close in AppRegistrationSheet(model: m, kind: k, close: close) }
    }
    static func openReplace(_ m: ConnectionsModel, _ c: ConnItem, done: Bool = false) {
        present(m, "connection-replace") { close in ReplaceTokenSheet(model: m, item: c, close: close, done: done) }
    }
    static func openRename(_ m: ConnectionsModel, _ c: ConnItem) {
        present(m, "connection-rename") { close in RenameSheet(model: m, item: c, close: close) }
    }
}

/// Advanced: paste a token, with plain step-by-step help. The token is sent once and never shown again.
struct TokenForm: View {
    let model: ConnectionsModel
    let kind: ConnKind
    /// Set when the token is for a connection that already exists (its "Use a token" link): the token replaces its
    /// sign-in, and its name, access and choices stay. One account stays one connection.
    var joining: ConnItem?
    let back: () -> Void
    let close: () -> Void
    @State private var name = ""
    @State private var token = ""
    @State private var fields: [String: String] = [:]

    var body: some View {
        CoreDialogPanel(kind.tokenTitle) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(intro).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                if joining == nil {
                    CoreTextField("Name", placeholder: "\(kind.name) (token)", text: $name, autofocus: true)
                }
                ForEach(kind.tokenFields, id: \.self) { f in
                    CoreTextField(
                        f, placeholder: f == "Site" ? "yourteam.atlassian.net" : "you@company.com", text: binding(f))
                }
                CoreSecureField("Token", placeholder: "Paste it here", text: $token)
                VStack(alignment: .leading, spacing: Space.s1) {
                    ForEach(Array(kind.tokenHelp.enumerated()), id: \.offset) { i, s in
                        Text("\(i + 1). \(s)").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    }
                }
                .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                .background(GlassInk.well, in: coreShape(Radius.cardMac))
                if let e = model.writeError[key] { AccIssue(text: say(e)) }
                if model.gated.contains(key) { TurnOnConnections(model: model) { await connect() } }
                AccDialogButtons(
                    confirm: joining == nil ? "Connect" : "Use this token", cancelTitle: "Back", busy: model.busy == key,
                    enabled: !token.isEmpty && kind.tokenFields.allSatisfy { !(fields[$0] ?? "").isEmpty }, cancel: back
                ) {
                    Task { await connect() }
                }
            }
        }
    }

    private var key: String { joining.map { "replace-\($0.id)" } ?? "token" }

    private var intro: String {
        guard let j = joining else {
            return "Only if signing in doesn't work for you. Core keeps the token sealed and never shows it again."
        }
        let who = j.label.isEmpty ? j.identity : j.label
        return "The token replaces the sign-in of \(who). Its name, access and \(kind.resource) stay. "
            + "It must be for the same \(kind.name) account. Core keeps it sealed and never shows it again."
    }

    /// A Core older than one-connection-per-account refuses a token on a signed-in connection with this sentence.
    private func say(_ e: String) -> String {
        e.contains("sign in again instead")
            ? "Your Core can't switch a signed-in connection to a token yet. Update the Core, then try again." : e
    }

    private func connect() async {
        if let j = joining {
            if await model.replaceToken(j, token: token, fields: fields) {
                await model.reload()
                await model.loadPicks()
                back()
            }
            return
        }
        let n = name.isEmpty ? "\(kind.name) (token)" : name
        if await model.addToken(kind: kind.id, name: n, fields: fields, token: token) { close() }
    }

    private func binding(_ f: String) -> Binding<String> {
        Binding(get: { fields[f] ?? "" }, set: { fields[f] = $0 })
    }
}

struct RenameSheet: View {
    let model: ConnectionsModel
    let item: ConnItem
    let close: () -> Void
    @State private var name = ""
    var body: some View {
        CoreDialogPanel("Rename \(item.name)") {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreTextField("Name", placeholder: item.name, text: $name, autofocus: true)
                if let e = model.writeError["rename-\(item.id)"] { AccIssue(text: e) }
                AccDialogButtons(
                    confirm: "Rename", busy: model.busy == "rename-\(item.id)", enabled: !name.isEmpty, cancel: close
                ) {
                    Task { if await model.rename(item, to: name.trimmingCharacters(in: .whitespaces)) { close() } }
                }
            }
        }
        .onAppear { name = item.name }
    }
}

/// Connections are off on the Core: one button turns them on (one Touch ID), then the refused action runs again. It says
/// what it is doing, what happened, and in words why it could not.
struct TurnOnConnections: View {
    let model: ConnectionsModel
    let retry: @MainActor () async -> Void

    var body: some View {
        switch model.turnOn {
        case .working:
            CoreNotice(
                symbol: "hourglass", title: "Turning on connections…", text: "Confirm with Touch ID.", tone: .queue)
        case .done:
            CoreNotice(symbol: "checkmark.circle", title: "Connections are on", text: "Trying again.", tone: .done)
        case .refused(let why):
            CoreNotice(
                symbol: "exclamationmark.triangle", title: "Couldn't turn on connections", text: why, tone: .fail
            ) {
                button("Try again")
            }
        case nil:
            CoreNotice(
                symbol: "switch.2", title: "Connections are turned off",
                text: "Turn them on here. You confirm with Touch ID, then it carries on.", tone: .warn
            ) { button("Turn on connections") }
        }
    }

    private func button(_ title: String) -> some View {
        Button(title) { Task { await model.turnOnConnections(then: retry) } }
            .buttonStyle(CoreButtonStyle(.prominent)).accessibilityIdentifier("connections-turn-on")
    }
}
