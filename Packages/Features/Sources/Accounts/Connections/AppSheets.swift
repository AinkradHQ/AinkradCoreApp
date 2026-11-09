import CoreUI
import SwiftUI

/// App registration: the OAuth app Ainkrad signs in with for one kind (client id and so on). Secrets are write-only: the
/// Core says only that one is set, and a blank secret field means "keep it". Only an admin can read or change it.
struct AppRegistrationSheet: View {
    let model: ConnectionsModel
    let kind: ConnKind
    let close: () -> Void
    @State private var state: ConnAppLoad = .loading
    @State private var values: [String: String] = [:]
    @State private var secrets: [String: String] = [:]

    private var key: String { "app-\(kind.id)" }

    var body: some View {
        CoreDialogPanel("\(kind.name) app registration", width: Space.s8 * 17) {
            VStack(alignment: .leading, spacing: Space.s3) {
                switch state {
                case .loading: AccSkeleton()
                case .failed(let why):
                    AccIssue(text: why)
                    AccDialogButtons(confirm: "Try again", cancelTitle: "Close", cancel: close) {
                        Task { await load() }
                    }
                case .readOnly:
                    CoreNotice(
                        symbol: "lock", title: "This Mac can only look",
                        text: "Changes need a Mac you allowed to manage the Core. Ask whoever runs it to set up the \(kind.name) app.")
                    AccDialogButtons(cancelTitle: "Close", cancel: close)
                case .ready(let app): form(app)
                }
            }
        }
        .task { await load() }
        .accessibilityIdentifier("connection-app")
    }

    @ViewBuilder private func form(_ app: ConnApp) -> some View {
        Text(
            app.configured
                ? "Core signs in to \(kind.name) with this app. Change a field to replace it."
                : "Core needs this app before anyone can sign in to \(kind.name)."
        )
        .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
        ForEach(app.fields) { f in
            if f.secret {
                CoreSecureField(
                    f.title, placeholder: f.isSet ? "Set. Type to replace it." : "Not set yet", text: secret(f.id)
                )
                .help(f.id)
            } else {
                CoreTextField(f.title, placeholder: "Not set yet", text: value(f.id)).help(f.id)
            }
        }
        if let r = app.redirect {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Give \(kind.name) this return address, exactly:").font(.system(size: MacTextSize.meta))
                    .foregroundStyle(GlassInk.secondary)
                Text(r).font(.system(size: MacTextSize.meta, design: .monospaced)).textSelection(.enabled)
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(GlassInk.well, in: coreShape(Radius.cardMac))
        }
        if app.configured {
            Label(
                "Changing the app can make existing \(kind.name) sign-ins ask to be signed in again.",
                systemImage: "info.circle"
            )
            .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let e = model.writeError[key] { AccIssue(text: e) }
        AccDialogButtons(confirm: "Save", busy: model.busy == key, enabled: !changes(app).isEmpty, cancel: close) {
            let sent = changes(app)
            Task {
                let ok = await model.saveApp(kind.id, fields: sent)
                // A secret lives in this sheet only: gone once the Core took it (or the sheet closes), kept after a refusal.
                if ok {
                    secrets = [:]
                    close()
                }
            }
        }
    }

    /// Only what the person changed: a typed secret, or a field whose text differs from what the Core has.
    func changes(_ app: ConnApp) -> [String: String] {
        var out: [String: String] = [:]
        for f in app.fields {
            if f.secret {
                if let s = secrets[f.id], !s.isEmpty { out[f.id] = s }
            } else if let v = values[f.id]?.trimmingCharacters(in: .whitespaces), !v.isEmpty, v != (f.value ?? "") {
                out[f.id] = v
            }
        }
        return out
    }

    private func load() async {
        state = .loading
        let s = await model.loadApp(kind.id)
        if case .ready(let app) = s {
            values = Dictionary(uniqueKeysWithValues: app.fields.map { ($0.id, $0.value ?? "") })
        }
        state = s
    }
    private func value(_ f: String) -> Binding<String> {
        Binding(get: { values[f] ?? "" }, set: { values[f] = $0 })
    }
    private func secret(_ f: String) -> Binding<String> {
        Binding(get: { secrets[f] ?? "" }, set: { secrets[f] = $0 })
    }
}

/// Replace token: a new token for a connection that was made with one. Write-only: Core never shows a token.
struct ReplaceTokenSheet: View {
    let model: ConnectionsModel
    let item: ConnItem
    let close: () -> Void
    @State private var token = ""
    @State private var fields: [String: String] = [:]
    @State private var done: Bool

    init(model: ConnectionsModel, item: ConnItem, close: @escaping () -> Void, done: Bool = false) {
        self.model = model
        self.item = item
        self.close = close
        _done = State(initialValue: done)
    }

    private var key: String { "replace-\(item.id)" }

    var body: some View {
        let k = model.kind(item.kind)
        CoreDialogPanel("Replace token for \(item.name)") {
            VStack(alignment: .leading, spacing: Space.s3) {
                if done {
                    CoreNotice(
                        symbol: "checkmark.circle", title: "Token replaced.",
                        text: "Core uses the new token from now on. The old one is gone.", tone: .done)
                    AccDialogButtons(cancelTitle: "Close", cancel: close)
                } else {
                    Text("Paste a new token for \(item.identity). Core keeps it sealed and never shows it again.")
                        .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(k?.tokenFields ?? [], id: \.self) { f in
                        CoreTextField(
                            f, placeholder: f == "Site" ? "yourteam.atlassian.net" : "you@company.com",
                            text: Binding(get: { fields[f] ?? "" }, set: { fields[f] = $0 }))
                    }
                    CoreSecureField("New token", placeholder: "Paste it here", text: $token, autofocus: true)
                    if let e = model.writeError[key] { AccIssue(text: e) }
                    AccDialogButtons(
                        confirm: "Replace", busy: model.busy == key,
                        enabled: !token.isEmpty && (k?.tokenFields ?? []).allSatisfy { !(fields[$0] ?? "").isEmpty },
                        cancel: close
                    ) {
                        let t = token
                        Task {
                            let ok = await model.replaceToken(item, token: t, fields: fields)
                            if ok {
                                token = ""  // not kept once the Core took it
                                done = true
                            }  // after a refusal the typed token stays, with the Core's reason above
                        }
                    }
                }
            }
        }
        .onAppear { if item.kind == "jira" { fields["Site"] = item.identity } }
        .accessibilityIdentifier("connection-replace")
    }
}
