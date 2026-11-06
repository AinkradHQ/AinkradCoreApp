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
                    "Provider",
                    segments: model.providers.map { CoreSegment($0.id, $0.name, symbol: ProviderLook.symbol($0.id)) },
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
                    Text("Same as Settings, Appearance.").font(.system(size: MacTextSize.meta))
                        .foregroundStyle(GlassInk.secondary)
                } else {
                    GlassSlider(value: $prefs.opacity, in: 0.05...1, low: "See-through", high: "Solid")
                }
            }
            GlassSection(
                "The Core app", sub: "Accounts, pools and bindings, shared by agents, Citadel and every device.",
                symbol: "creditcard.fill", hue: GlassInk.blue, index: 1
            ) {
                AppActionTile(
                    title: "Open", symbol: "arrow.up.forward.app", key: "", hue: GlassInk.blue, prominent: true
                ) {
                    model.host.shell.overlay = nil
                    model.show(.overview)
                }
            } content: {
                EmptyView()
            }
        }
        .foregroundStyle(GlassInk.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Settings, Security: where the real-accounts gate stands.
/// Settings, Security, Real accounts: the way from no keys to real provider keys, as three steps in plain words. The next
/// step to take glows and has the tile that opens it.
struct AccountsGateSection: View {
    let model: AccountsModel

    var body: some View {
        let g = model.gate
        let done = [(g.mode ?? 0) >= 1, (g.providerAccounts ?? 0) >= 1 && g.kind == .real]
        let next = done.firstIndex(of: false)
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(
                "Real accounts hold a real API key from Anthropic, OpenAI or Google. Two switches stand in the way, on purpose."
            )
            .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            verdict(g)
            VStack(spacing: Space.s3) {
                step(
                    1, "Keys and secrets", "Your Core may keep keys and secrets.",
                    off: "Your Core keeps no keys at all yet.", symbol: "testtube.2", done: done[0], next: next == 0)
                step(
                    2, "Real provider keys", "Accounts may hold a real key. Agents can use it.",
                    off: "Only test keys are accepted for accounts.", symbol: "key.fill", done: done[1],
                    next: next == 1)
                step(
                    3, "Add a real account", "Connect Claude, OpenAI or Gemini in Accounts.",
                    off: next == nil
                        ? "Connect Claude, OpenAI or Gemini in Accounts." : "Opens once the two steps above are done.",
                    symbol: "person.crop.circle.badge.plus",
                    done: false, next: next == nil,
                    open: (
                        "Open Accounts",
                        {
                            model.host.shell.overlay = nil
                            model.show(.accounts)
                        }
                    ))
            }
            HStack(spacing: Space.s3) {
                fact("eye.slash.fill", "Never shown again", "A key goes in and can't be read back.")
                fact("server.rack", "Only runners use it", "Your Mac never holds it.")
                fact("doc.text.fill", "Every use is logged", "See it in Audit.")
            }
        }
        .foregroundStyle(GlassInk.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(g.technical)
        .animation(.smooth(duration: 0.35), value: g)
        .task { await model.reload() }
    }

    private func verdict(_ g: GateState) -> some View {
        let hue = g.kind == .real ? GlassInk.green : g.kind == .off ? GlassInk.orange : GlassInk.blue
        return HStack(spacing: Space.s4) {
            IconTile(
                g.kind == .real ? "checkmark.shield.fill" : g.kind == .off ? "lock.fill" : "testtube.2", hue: hue,
                size: 56, bounce: g.step ?? -1
            )
            .shadow(color: hue.opacity(0.5), radius: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(g.title).font(.system(size: MacTextSize.large, weight: .bold)).foregroundStyle(hue)
                Text(g.detail).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            if let s = g.step { StepTrack(["Off", "Test keys", "Real keys"], at: s, hue: hue) }
        }
        .padding(Space.s4)
        .background(hue.opacity(0.1), in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(hue.opacity(0.4), lineWidth: 1) }
    }

    private func step(
        _ n: Int, _ title: String, _ on: String, off: String, symbol: String, done: Bool, next: Bool,
        open: (String, () -> Void)? = nil
    ) -> some View {
        let hue = done ? GlassInk.green : next ? GlassInk.blue : GlassInk.slate
        return HStack(spacing: Space.s3) {
            IconTile(done ? "checkmark" : symbol, hue: hue, size: 40, bounce: done)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(n). \(title)").font(.system(size: MacTextSize.headline, weight: .semibold))
                Text(done ? on : off).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s3)
            if done {
                Label("Done", systemImage: "checkmark.circle.fill").font(
                    .system(size: MacTextSize.meta, weight: .semibold)
                )
                .foregroundStyle(GlassInk.green)
            } else if next {
                let o = open ?? ("Open Feature switches", { model.openSwitches() })
                AppActionTile(
                    title: o.0, symbol: "arrow.right", key: "↩", hue: GlassInk.blue, prominent: true, run: o.1
                )
                .keyboardShortcut(.defaultAction)
            } else {
                Label("Waiting", systemImage: "lock.fill").font(.system(size: MacTextSize.meta))
                    .foregroundStyle(GlassInk.secondary)
            }
        }
        .padding(Space.s3)
        .background(next ? GlassInk.blue.opacity(0.1) : GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay {
            coreShape(Radius.cardMac).strokeBorder(
                next ? GlassInk.blue.opacity(0.5) : GlassInk.wellEdge, lineWidth: next ? 1.5 : 1)
        }
        .shadow(color: GlassInk.blue.opacity(next ? 0.25 : 0), radius: 12)
        .opacity(done || next ? 1 : 0.7)
    }

    private func fact(_ symbol: String, _ title: String, _ line: String) -> some View {
        HStack(spacing: Space.s2) {
            IconTile(symbol, hue: GlassInk.slate, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: MacTextSize.body, weight: .semibold))
                Text(line).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3).frame(maxWidth: .infinity)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
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
