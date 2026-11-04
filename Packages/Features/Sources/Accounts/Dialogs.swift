import CoreUI
import Shell
import SwiftUI

/// The dialogs of the Core app, shown over the shell like the Devices and Secrets dialogs.
@MainActor
enum AccountDialogs {
    private static func present<V: View>(
        _ m: AccountsModel, _ id: String, @ViewBuilder _ v: @escaping (@escaping () -> Void) -> V
    ) {
        m.host.clearElevationNotice()
        let shell = m.host.shell
        shell.present(
            ShellDialog(id: id, onClose: { [weak m] in m?.host.clearElevationNotice() }) { v { shell.closeDialog() } })
    }

    static func openConnect(_ m: AccountsModel, provider: String?, replacing: AccountItem? = nil) {
        present(m, "account-connect") { close in
            ConnectDialog(model: m, provider: provider, replacing: replacing, close: close)
        }
    }
    static func openDelete(_ m: AccountsModel, _ a: AccountItem) {
        present(m, "account-delete") { close in DeleteAccountDialog(model: m, account: a, close: close) }
    }
    static func openCap(_ m: AccountsModel, _ a: AccountItem) {
        present(m, "account-cap") { close in CapDialog(model: m, account: a, close: close) }
    }
    static func openNewPool(_ m: AccountsModel) {
        present(m, "pool-new") { close in NewPoolDialog(model: m, close: close) }
    }
    static func openDeletePool(_ m: AccountsModel, _ p: PoolItem) {
        present(m, "pool-delete") { close in DeletePoolDialog(model: m, pool: p, close: close) }
    }
    static func openAddMember(_ m: AccountsModel, pool: PoolItem) {
        present(m, "pool-member") { close in AddMemberDialog(model: m, pool: pool, close: close) }
    }
    static func openBind(_ m: AccountsModel, pool: PoolItem?) {
        present(m, "binding-new") { close in BindDialog(model: m, pool: pool, close: close) }
    }
}

/// Connect an account, or use a new key. Sign-in happens on the provider's own page: this dialog opens it and never holds a
/// key, a token or a field to type one in.
private struct ConnectDialog: View {
    let model: AccountsModel
    let replacing: AccountItem?
    let close: () -> Void
    @State private var provider: String
    @Environment(\.corePalette) private var palette

    init(model: AccountsModel, provider: String?, replacing: AccountItem?, close: @escaping () -> Void) {
        self.model = model
        self.replacing = replacing
        self.close = close
        _provider = State(
            initialValue: provider ?? model.providers.first { ProviderSites.page($0.id) != nil }?.id ?? model.providers
                .first?.id ?? "")
    }

    var body: some View {
        let site = ProviderSites.page(provider)
        CoreDialogPanel(replacing.map { "New key for \($0.label)" } ?? "Connect an account") {
            VStack(alignment: .leading, spacing: Space.s3) {
                if replacing == nil {
                    CoreFieldLabel("Provider")
                    CoreSegmented(
                        "Provider", segments: model.providers.map { CoreSegment($0.id, $0.name) }, selection: $provider)
                }
                step(
                    1, "Get a key on the provider's own page",
                    detail: site.map { "Create a key in \($0.name). Ainkrad never sees your password." }
                        ?? "Open this provider's own site and create a key there."
                ) {
                    if let site {
                        Button {
                            model.opener(site.url)
                        } label: {
                            Label("Open \(site.name)", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.coreProminent).help(site.url.absoluteString)
                    } else {
                        Text("No page is known for \(model.providerName(provider)).").foregroundStyle(palette.text2)
                    }
                }
                step(
                    2, "Add it to Core from an admin device",
                    detail:
                        "Core stores a key only when an admin device sends it. This app has no field for a key or a token, on purpose, so it cannot finish this step."
                ) {
                    EmptyView()
                }
                AccDialogButtons(confirm: "Done", cancel: close, run: close)
            }
        }
        .accessibilityIdentifier("account-connect")
    }

    private func step<C: View>(_ n: Int, _ title: String, detail: String, @ViewBuilder _ action: () -> C) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Text("\(n)").font(.system(size: MacTextSize.meta, weight: .semibold)).frame(
                width: Space.s5, height: Space.s5
            )
            .background(palette.uDim, in: coreShape(Radius.chip)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
                Text(detail).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                action()
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct DeleteAccountDialog: View {
    let model: AccountsModel
    let account: AccountItem
    let close: () -> Void
    @State private var busy = false
    var body: some View {
        let pools = model.pools(of: account)
        CoreDialogPanel("Delete \(account.label)?", width: Space.s8 * 14) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(
                    "Its key is deleted from Core and cannot be recovered. Its leases are dropped.\(pools.isEmpty ? "" : " It leaves \(pools.map(\.name).joined(separator: ", ")).")"
                )
                .fixedSize(horizontal: false, vertical: true)
                Text("Revoke the key at the provider too. Core cannot do that for you.").font(
                    .system(size: MacTextSize.meta))
                if let e = model.writeError["delete-\(account.id)"] { AccIssue(text: e) }
                AccNotice(notice: model.host.elevationNotice)
                AccDialogButtons(confirm: "Delete account", danger: true, busy: busy, cancel: close) {
                    busy = true
                    Task {
                        let ok = await model.delete(account)
                        busy = false
                        if ok { close() }
                    }
                }
            }
        }
        .accessibilityIdentifier("account-delete")
    }
}

private struct CapDialog: View {
    let model: AccountsModel
    let account: AccountItem
    let close: () -> Void
    @State private var text: String
    @State private var busy = false
    init(model: AccountsModel, account: AccountItem, close: @escaping () -> Void) {
        self.model = model
        self.account = account
        self.close = close
        _text = State(initialValue: account.cap == 0 ? "" : String(account.cap))
    }
    private var parsed: Int64? {
        let t = text.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? 0 : Int64(t)
    }
    private var issue: String? {
        guard let n = parsed, (0...64).contains(n) else {
            return "Use a whole number from 0 to 64. Leave it empty for no limit."
        }
        return nil
    }
    var body: some View {
        CoreDialogPanel("Sessions at once: \(account.label)", width: Space.s8 * 13) {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreTextField(
                    "Limit", placeholder: "No limit", text: $text, error: text.isEmpty ? nil : issue, autofocus: true
                ) { go() }
                Text("Over the limit, new sessions take another account or wait.").font(.system(size: MacTextSize.meta))
                if let e = model.writeError["cap-\(account.id)"] { AccIssue(text: e) }
                AccNotice(notice: model.host.elevationNotice)
                AccDialogButtons(confirm: "Save", busy: busy, enabled: issue == nil, cancel: close) { go() }
            }
        }
        .accessibilityIdentifier("account-cap")
    }
    private func go() {
        guard issue == nil, let n = parsed else { return }
        busy = true
        Task {
            let ok = await model.setCap(account, n)
            busy = false
            if ok { close() }
        }
    }
}

private struct NewPoolDialog: View {
    let model: AccountsModel
    let close: () -> Void
    @State private var name = ""
    @State private var provider = ""
    @State private var busy = false
    var body: some View {
        let chosen = provider.isEmpty ? (model.providers.first?.id ?? "") : provider
        CoreDialogPanel("New pool", width: Space.s8 * 14) {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreTextField("Name", placeholder: "client-work", text: $name, autofocus: true) { go(chosen) }
                CoreFieldLabel("Provider")
                CoreSegmented(
                    "Provider", segments: model.providers.map { CoreSegment($0.id, $0.name) },
                    selection: Binding(get: { chosen }, set: { provider = $0 }))
                Text("A pool holds accounts of one provider. It starts empty.").font(.system(size: MacTextSize.meta))
                let typed = name.trimmingCharacters(in: .whitespaces)
                if !typed.isEmpty && !PoolName.isValid(typed) {
                    AccIssue(text: PoolName.rule)
                }
                if let e = model.writeError["new-pool"] { AccIssue(text: e) }
                AccNotice(notice: model.host.elevationNotice)
                AccDialogButtons(
                    confirm: "Create pool", busy: busy,
                    enabled: PoolName.isValid(name.trimmingCharacters(in: .whitespaces)) && !chosen.isEmpty,
                    cancel: close
                ) { go(chosen) }
            }
        }
        .accessibilityIdentifier("pool-new")
    }
    private func go(_ p: String) {
        guard PoolName.isValid(name.trimmingCharacters(in: .whitespaces)) else { return }
        busy = true
        Task {
            let ok = await model.createPool(name: name, provider: p)
            busy = false
            if ok { close() }
        }
    }
}

private struct DeletePoolDialog: View {
    let model: AccountsModel
    let pool: PoolItem
    let close: () -> Void
    @State private var busy = false
    var body: some View {
        let n = model.bindings(of: pool).count
        CoreDialogPanel("Delete \(pool.name)?", width: Space.s8 * 14) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(
                    "The pool goes, and so do its \(n) binding\(n == 1 ? "" : "s"). Those agents fall back to the default pool. The accounts stay."
                )
                .fixedSize(horizontal: false, vertical: true)
                if let e = model.writeError["delete-pool-\(pool.id)"] { AccIssue(text: e) }
                AccNotice(notice: model.host.elevationNotice)
                AccDialogButtons(confirm: "Delete pool", danger: true, busy: busy, cancel: close) {
                    busy = true
                    Task {
                        let ok = await model.delete(pool)
                        busy = false
                        if ok { close() }
                    }
                }
            }
        }
        .accessibilityIdentifier("pool-delete")
    }
}

private struct AddMemberDialog: View {
    let model: AccountsModel
    let pool: PoolItem
    let close: () -> Void
    @State private var pick: Int64?
    @State private var busy = false
    var body: some View {
        let rest = model.candidates(for: pool)
        CoreDialogPanel("Add to \(pool.name)", width: Space.s8 * 14) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if rest.isEmpty {
                    Text("Every \(model.providerName(pool.provider)) account is already in this pool.")
                } else {
                    CoreFieldLabel("Account")
                    ForEach(rest) { a in
                        CoreRow(
                            a.label, subtitle: a.phase.label, symbol: "key", selected: (pick ?? rest[0].id) == a.id,
                            action: { pick = a.id }
                        ) { EmptyView() }
                    }
                    Text("It goes last in the fallback order.").font(.system(size: MacTextSize.meta))
                }
                if let e = model.writeError["member-\(pool.id)"] { AccIssue(text: e) }
                AccNotice(notice: model.host.elevationNotice)
                AccDialogButtons(confirm: "Add account", busy: busy, enabled: !rest.isEmpty, cancel: close) {
                    guard let a = rest.first(where: { $0.id == (pick ?? rest[0].id) }) else { return }
                    busy = true
                    Task {
                        let ok = await model.add(a, to: pool)
                        busy = false
                        if ok { close() }
                    }
                }
            }
        }
        .accessibilityIdentifier("pool-member")
    }
}

private struct BindDialog: View {
    let model: AccountsModel
    let close: () -> Void
    @State private var agent = ""
    @State private var provider: String
    @State private var poolID: Int64?
    @State private var busy = false
    init(model: AccountsModel, pool: PoolItem?, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        let first = pool ?? model.selectedPool
        _provider = State(initialValue: first?.provider ?? "")
        _poolID = State(initialValue: pool?.id)
    }
    var body: some View {
        let providers = Array(Set(model.pools.map(\.provider))).sorted()
        let chosen = providers.contains(provider) ? provider : (providers.first ?? "")
        let pools = model.pools(for: chosen)
        let target = pools.first { $0.id == poolID } ?? model.defaultPool(chosen) ?? pools.first
        let t = agent.trimmingCharacters(in: .whitespaces)
        CoreDialogPanel("Bind an agent", width: Space.s8 * 15) {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreTextField(
                    "Agent", placeholder: "agent id", text: $agent,
                    error: t.isEmpty || AccountsModel.validAgent(t) ? nil : "1 to 64 letters, digits or . _ : -",
                    mono: true, autofocus: true
                ) { go(target) }
                CoreFieldLabel("Provider")
                CoreSegmented(
                    "Provider", segments: providers.map { CoreSegment($0, model.providerName($0)) },
                    selection: Binding(
                        get: { chosen },
                        set: {
                            provider = $0
                            poolID = nil
                        }))
                CoreFieldLabel("Pool")
                CoreSegmented(
                    "Pool", segments: pools.map { CoreSegment($0.id, $0.name) },
                    selection: Binding(get: { target?.id ?? -1 }, set: { poolID = $0 }))
                Text("It replaces an earlier binding of this agent for the same provider.").font(
                    .system(size: MacTextSize.meta))
                if let e = model.writeError["bind"] { AccIssue(text: e) }
                AccNotice(notice: model.host.elevationNotice)
                AccDialogButtons(
                    confirm: "Bind agent", busy: busy, enabled: AccountsModel.validAgent(t) && target != nil,
                    cancel: close
                ) { go(target) }
            }
        }
        .accessibilityIdentifier("binding-new")
    }
    private func go(_ p: PoolItem?) {
        guard let p, AccountsModel.validAgent(agent.trimmingCharacters(in: .whitespaces)) else { return }
        busy = true
        Task {
            let ok = await model.bind(agent: agent, to: p)
            busy = false
            if ok { close() }
        }
    }
}

/// Settings, Core: a way into the Core app.
struct AccountsLinkSection: View {
    let model: AccountsModel
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(
                "Accounts, pools and bindings have their own Core app, because agents, Citadel and every device share them."
            )
            .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            Button("Open Core") {
                model.host.shell.overlay = nil
                model.show(.overview)
            }
            .buttonStyle(.coreProminent)
        }
        .font(.system(size: MacTextSize.body)).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Settings, Security: where the real-accounts gate stands.
struct AccountsGateSection: View {
    let model: AccountsModel
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("This gate is only for provider keys. Other secrets stay throwaway until the external review ends.")
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            CoreNotice(
                symbol: model.gate.symbol, title: model.gate.title, text: model.gate.detail, tone: model.gate.tone
            ) {
                Button("Feature switches") { model.openSwitches() }.buttonStyle(.coreSecondary)
            }
        }
        .font(.system(size: MacTextSize.body)).frame(maxWidth: .infinity, alignment: .leading)
        .task { await model.reload() }
    }
}

/// The Core's rule for a pool name (`[a-z][a-z0-9._-]{0,63}`), so a name it would refuse is explained before the Touch ID prompt.
enum PoolName {
    static let rule = "Use lowercase letters, digits, dots, dashes or underscores, starting with a letter (up to 64)."
    static func isValid(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, name.unicodeScalars.count <= 64, ("a"..."z").contains(first)
        else { return false }
        return name.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) || "._-".unicodeScalars.contains($0)
        }
    }
}
