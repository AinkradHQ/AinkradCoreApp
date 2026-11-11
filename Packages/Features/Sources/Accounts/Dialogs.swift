import CoreUI
import Shell
import SwiftUI

/// The dialogs of the Core app, shown over the shell like the Devices and Secrets dialogs.
@MainActor
enum AccountDialogs {
    static func present<V: View>(
        _ m: AccountsModel, _ id: String, @ViewBuilder _ v: @escaping (@escaping () -> Void) -> V
    ) {
        m.host.clearElevationNotice()
        let shell = m.host.shell
        shell.present(
            ShellDialog(
                id: id,
                onClose: { [weak m] in
                    m?.host.clearElevationNotice()
                    m?.dialogClosed()
                }
            ) { v { shell.closeDialog() } })
    }

    /// A new account opens the wizard (N22); a new key for an account, or a scripted flow, opens the one-page dialog.
    static func openConnect(
        _ m: AccountsModel, provider: String?, replacing: AccountItem? = nil, flow: KeyEntryFlow? = nil,
        advanced: Bool = false
    ) {
        present(m, "account-connect") { close in
            if replacing == nil && flow == nil {
                ConnectWizard(model: m, provider: provider, advanced: advanced, close: close)
            } else {
                ConnectDialog(model: m, provider: provider, replacing: replacing, flow: flow, close: close)
            }
        }
    }
    static func openDelete(_ m: AccountsModel, _ a: AccountItem) {
        present(m, "account-delete") { close in DeleteAccountDialog(model: m, account: a, close: close) }
    }
    static func openCap(_ m: AccountsModel, _ a: AccountItem) {
        present(m, "account-cap") { close in CapDialog(model: m, account: a, close: close) }
    }
    static func openLimits(_ m: AccountsModel, _ a: AccountItem) {
        present(m, "account-limits") { close in LimitsDialog(model: m, account: a, close: close) }
    }
    static func openBudget(_ m: AccountsModel, editing: BudgetItem?) {
        present(m, "budget") { close in BudgetDialog(model: m, editing: editing, close: close) }
    }
    static func openRaise(_ m: AccountsModel, _ b: BudgetItem) {
        present(m, "budget-raise") { close in RaiseDialog(model: m, budget: b, close: close) }
    }
    static func openDeleteBudget(_ m: AccountsModel, _ b: BudgetItem) {
        present(m, "budget-delete") { close in DeleteBudgetDialog(model: m, budget: b, close: close) }
    }
    static func openPrice(_ m: AccountsModel, editing: PriceItem?) {
        present(m, "price") { close in PriceDialog(model: m, editing: editing, close: close) }
    }
    static func openProvider(_ m: AccountsModel, editing: ProviderItem?) {
        present(m, "provider") { close in ProviderDialog(model: m, editing: editing, close: close) }
    }
    static func openDeleteProvider(_ m: AccountsModel, _ p: ProviderItem) {
        present(m, "provider-delete") { close in DeleteProviderDialog(model: m, provider: p, close: close) }
    }
    static func openNewPool(_ m: AccountsModel, reason: String? = nil) {
        m.note("new-pool", reason)
        present(m, "pool-new") { close in NewPoolDialog(model: m, close: close) }
    }
    static func openDeletePool(_ m: AccountsModel, _ p: PoolItem) {
        present(m, "pool-delete") { close in DeletePoolDialog(model: m, pool: p, close: close) }
    }
    static func openAddMember(_ m: AccountsModel, pool: PoolItem) {
        present(m, "pool-member") { close in AddMemberDialog(model: m, pool: pool, close: close) }
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
                Text("Revoke the key at the provider too. Core cannot do that for you.").coreFont(
                    size: MacTextSize.meta)
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
                Text("Over the limit, new sessions take another account or wait.").coreFont(size: MacTextSize.meta)
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
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Space.s2), GridItem(.flexible(), spacing: Space.s2)],
                    spacing: Space.s2
                ) {
                    ForEach(ProviderLook.ordered(model.providers)) { p in
                        AccPick(
                            title: p.name, sub: p.loginMethods.contains("browser_code") ? "Subscription" : "API key",
                            symbol: ProviderLook.symbol(p.id), hue: GlassInk.blue, on: p.id == chosen
                        ) { provider = p.id }
                    }
                }
                Text("A pool holds accounts of one provider. It starts empty.").coreFont(size: MacTextSize.meta)
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
        let used = model.chains(using: pool)
        CoreDialogPanel("Delete \(pool.name)?", width: Space.s8 * 14) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(
                    used.isEmpty
                        ? "The pool goes. The accounts stay."
                        : "\(used.map(\.name).joined(separator: ", ")) still uses this pool, so it can't be deleted yet. Take it out of the chain first."
                )
                .fixedSize(horizontal: false, vertical: true)
                if let c = used.first {
                    AccLink(title: "Open \(c.name)", symbol: "link") {
                        close()
                        model.chainSelection = c.id
                        model.page = .chains
                        model.detail = nil
                    }
                }
                if let e = model.writeError["delete-pool-\(pool.id)"] { AccIssue(text: e) }
                AccNotice(notice: model.host.elevationNotice)
                AccDialogButtons(confirm: "Delete pool", danger: true, busy: busy, enabled: used.isEmpty, cancel: close)
                {
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
                            a.label, subtitle: model.verdict(a).label, symbol: "key",
                            selected: (pick ?? rest[0].id) == a.id,
                            action: { pick = a.id }
                        ) { EmptyView() }
                    }
                    Text("It goes last in the fallback order.").coreFont(size: MacTextSize.meta)
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

/// Settings, Core: a way into the Core app.
struct AccountsLinkSection: View {
    let model: AccountsModel
    @Bindable private var prefs = AccountsPrefs.shared
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            GlassSection(
                "Look", sub: "The Core app's content background.", symbol: "circle.lefthalf.filled",
                hue: GlassInk.blue
            ) {
                AppLookTabs(follow: $prefs.followLook, mode: $prefs.modeChoice)
            } content: {
                if prefs.followLook {
                    Text("Same as Settings, Appearance.").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary)
                } else {
                    GlassSlider(value: $prefs.opacity, in: 0.05...1, low: "See-through", high: "Solid")
                }
            }
            GlassSection(
                "The Core app", sub: "Accounts, pools and chains, shared by agents, Citadel and every device.",
                symbol: "creditcard.fill", hue: GlassInk.blue, index: 1
            ) {
                AppActionTile(
                    title: "Open", symbol: "arrow.up.forward.app", key: "", hue: GlassInk.blue, prominent: true
                ) {
                    model.host.shell.overlay = nil
                    model.show(.accounts)
                }
            } content: {
                EmptyView()
            }
        }
        .foregroundStyle(GlassInk.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
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
