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

    /// CN2. With a kind, its sign-in starts at once; without, the person picks one first.
    static func openConnect(_ m: ConnectionsModel, kind: String?, again: Int64? = nil) {
        m.again = again
        present(m, "connection-connect", onClose: { [weak m] in m?.stopFlow() }) { close in
            ConnectSheet(model: m, close: close, picked: kind)
        }
    }
    static func openAccess(_ m: ConnectionsModel, _ c: ConnItem) {
        present(m, "connection-access") { close in AccessSheet(model: m, item: c, close: close) }
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
    static func openDisconnect(_ m: ConnectionsModel, _ c: ConnItem) {
        present(m, "connection-delete") { close in
            CoreDialogPanel("Disconnect \(c.name)?") {
                VStack(alignment: .leading, spacing: Space.s4) {
                    CoreNotice(
                        symbol: "exclamationmark.triangle", title: "AI sessions lose access to \(c.identity).",
                        text:
                            "Running sessions keep going but can't reach \(m.kind(c.kind)?.name ?? c.kind). You can connect it again later.",
                        tone: .warn)
                    AccDialogButtons(confirm: "Disconnect", cancelTitle: "Keep it", danger: true, cancel: close) {
                        Task { if await m.disconnect(c) { close() } }
                    }
                }
            }
        }
    }
}

/// CN2: pick a service, then sign in on its own site with live steps; "(advanced)…" pastes a token instead.
struct ConnectSheet: View {
    let model: ConnectionsModel
    let close: () -> Void
    @State var picked: String?
    @State private var advanced = false
    @State private var site: String?

    var body: some View {
        Group {
            if let k = picked.flatMap(model.kind) {
                if advanced {
                    TokenForm(model: model, kind: k, back: { advanced = false }, close: close)
                } else {
                    flowView(k)
                }
            } else {
                pickView
            }
        }
        .animation(.smooth(duration: 0.3), value: picked)
        .animation(.smooth(duration: 0.3), value: advanced)
        .task(id: picked) { if let p = picked, !advanced { await model.startFlow(p) } }
        .accessibilityIdentifier("connection-connect")
    }

    private var pickView: some View {
        CoreDialogPanel("Connect a service") {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Pick one. You sign in on its own website; Core never asks for a password.")
                    .foregroundStyle(GlassInk.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Space.s2) {
                    ForEach(model.liveKinds) { k in
                        AccPick(
                            title: k.name, sub: k.say, symbol: ConnLook.symbol(k.id), hue: GlassInk.blue, on: false
                        ) { picked = k.id }
                    }
                }
                AccDialogButtons(cancel: close)
            }
        }
    }

    @ViewBuilder private func flowView(_ k: ConnKind) -> some View {
        let f = model.flow
        switch f?.step {
        case .failed(let title, let fix):
            CoreDialogPanel("Sign-in didn't finish") {
                VStack(alignment: .leading, spacing: Space.s4) {
                    CoreNotice(symbol: "exclamationmark.triangle", title: title, text: fix, tone: .fail)
                    if f?.gated == true {
                        TurnOnConnections(model: model) { await model.startFlow(k.id) }
                    }
                    AccDialogButtons(confirm: "Try again", cancel: close) {
                        Task { await model.startFlow(k.id) }
                    }
                }
            }
        case .connected(let id):
            CoreDialogPanel("Connected") {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("Your AI sessions can use it now.").foregroundStyle(GlassInk.secondary)
                    if !model.picked.isEmpty { PickedList(kind: k.resource, names: model.picked) }
                    if let c = model.item(id) {
                        AccPanel {
                            HStack(spacing: Space.s3) {
                                ConnTile(kind: c.kind)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(c.name).coreFont(size: MacTextSize.body, weight: .semibold)
                                    Text("\(c.identity) · \(model.access(c))").coreFont(size: MacTextSize.meta)
                                        .foregroundStyle(GlassInk.secondary)
                                }
                                Spacer()
                                StateBadge("Connected", tone: .done, symbol: "checkmark.circle")
                            }
                        }
                    }
                    AccDialogButtons(
                        confirm: "Who can use it", cancelTitle: "Close", cancel: close,
                        run: {
                            close()
                            if let c = model.item(id) { ConnDialogs.openAccess(model, c) }
                        })
                }
            }
        default:
            signIn(k, f)
        }
    }

    private func signIn(_ k: ConnKind, _ f: ConnFlow?) -> some View {
        let gh = k.signIn == .deviceCode
        let steps =
            gh
            ? ["Sign in to GitHub", "Choose repositories", "Connected"]
            : ["Sign in with Atlassian", "Pick your site", "Connected"]
        let at: Int =
            switch f?.step {
            case .chooseResources, .pickSite: 1
            default: 0
            }
        return CoreDialogPanel("Sign in with \(k.name)") {
            VStack(alignment: .leading, spacing: Space.s4) {
                switch f?.step {
                case .chooseResources(let login, _):
                    Text(
                        "Signed in as \(login). Step 2: choose the repositories Core may reach. GitHub shows the list."
                    )
                    .foregroundStyle(GlassInk.secondary)
                case .pickSite:
                    Text("You have access to more than one site. Pick one; connect the other later if you need it.")
                        .foregroundStyle(GlassInk.secondary)
                default:
                    Text(
                        gh
                            ? "Enter this code on github.com. It works for 15 minutes."
                            : "Your browser opens Atlassian. Sign in and press Accept, then come back here."
                    ).foregroundStyle(GlassInk.secondary)
                }
                if gh, case .waiting? = f?.step, let code = f?.userCode {
                    VStack(spacing: Space.s2) {
                        Text(code).coreFont(size: 34, weight: .semibold, design: .monospaced).textSelection(
                            .enabled
                        )
                        .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
                        Text("GitHub asks for this code after you sign in.").coreFont(size: MacTextSize.meta)
                            .foregroundStyle(GlassInk.secondary)
                        HStack {
                            AccLink(title: "Copy code", symbol: "doc.on.doc") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(code, forType: .string)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity).padding(Space.s4)
                    .background(GlassInk.well, in: coreShape(Radius.cardMac))
                }
                StepList(steps: steps, at: at)
                if case .pickSite(let sites)? = f?.step {
                    VStack(spacing: Space.s1) {
                        ForEach(sites, id: \.self) { s in
                            AccPick(
                                title: s.split(separator: ".").first.map { String($0).capitalized } ?? s, sub: s,
                                symbol: ConnLook.symbol(k.id), hue: ConnLook.hue(k.id), on: (site ?? sites.first) == s
                            ) { site = s }
                        }
                    }
                }
                footer(k, f)
            }
        }
    }

    @ViewBuilder private func footer(_ k: ConnKind, _ f: ConnFlow?) -> some View {
        HStack(spacing: Space.s2) {
            Button("Cancel", action: close).buttonStyle(CoreButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction).environment(\.coreKeycap, "esc")
            switch f?.step {
            case .chooseResources:
                Button("Skip for now") { Task { await model.choose(site: nil) } }
                    .buttonStyle(CoreButtonStyle(.secondary))
                Spacer(minLength: Space.s3)
                Button(model.installing ? "Waiting for GitHub…" : "Choose repositories") { model.openInstall() }
                    .buttonStyle(CoreButtonStyle(.prominent)).disabled(model.installing)
                    .keyboardShortcut(.defaultAction).environment(\.coreKeycap, "↩")
            case .pickSite(let sites):
                Spacer(minLength: Space.s3)
                Button("Use this site") { Task { await model.choose(site: site ?? sites.first) } }
                    .buttonStyle(CoreButtonStyle(.prominent))
                    .keyboardShortcut(.defaultAction).environment(\.coreKeycap, "↩")
            default:
                if !k.tokenTitle.isEmpty {
                    Button("(advanced)…") { advanced = true }.buttonStyle(CoreButtonStyle(.secondary))
                }
                Spacer(minLength: Space.s3)
                Button(k.signIn == .deviceCode ? "Sign in with GitHub" : "Sign in with Atlassian") {
                    model.openSignIn()
                }
                .buttonStyle(CoreButtonStyle(.prominent)).disabled(f == nil)
                .keyboardShortcut(.defaultAction).environment(\.coreKeycap, "↩")
            }
        }
    }
}

/// Live steps: done ones ticked, the current one marked, the rest quiet.
struct StepList: View {
    let steps: [String]
    let at: Int
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: Space.s2) {
                    Image(systemName: i < at ? "checkmark.square.fill" : i == at ? "square.inset.filled" : "square")
                        .foregroundStyle(i < at ? GlassInk.green : i == at ? GlassInk.blue : GlassInk.secondary)
                        .symbolEffect(.pulse, options: .repeating, isActive: i == at && !reduce)
                        .contentTransition(.symbolEffect(.replace))
                    Text(s).foregroundStyle(i <= at ? GlassInk.primary : GlassInk.secondary)
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: at)
        .accessibilityElement(children: .combine)
    }
}

/// Advanced: paste a token, with plain step-by-step help. The token is sent once and never shown again.
struct TokenForm: View {
    let model: ConnectionsModel
    let kind: ConnKind
    let back: () -> Void
    let close: () -> Void
    @State private var name = ""
    @State private var token = ""
    @State private var fields: [String: String] = [:]

    var body: some View {
        CoreDialogPanel(kind.tokenTitle) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Only if signing in doesn't work for you. Core keeps the token sealed and never shows it again.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                CoreTextField("Name", placeholder: "\(kind.name) (token)", text: $name, autofocus: true)
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
                if let e = model.writeError["token"] { AccIssue(text: e) }
                if model.gated.contains("token") { TurnOnConnections(model: model) { await connect() } }
                AccDialogButtons(
                    confirm: "Connect", cancelTitle: "Back", busy: model.busy == "token",
                    enabled: !token.isEmpty && kind.tokenFields.allSatisfy { !(fields[$0] ?? "").isEmpty }, cancel: back
                ) {
                    Task { await connect() }
                }
            }
        }
    }

    private func connect() async {
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

/// GitHub: the repositories the person picked, a few by name.
struct PickedList: View {
    let kind: String
    let names: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("You chose \(names.count) \(names.count == 1 ? String(kind.dropLast()) : kind)").coreFont(
                size: MacTextSize.meta, weight: .semibold)
            ForEach(names.prefix(5), id: \.self) { Text($0).coreFont(size: MacTextSize.meta, design: .monospaced) }
            if names.count > 5 {
                Text("and \(names.count - 5) more").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .combine)
    }
}
