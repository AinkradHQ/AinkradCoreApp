import CoreUI
import Shell
import SwiftUI

/// One usage limit of an account and where it stands now (`GET /accounts/usage`). `unit` is `tokens` or `messages`.
struct LimitItem: Identifiable, Equatable, Sendable {
    let unit: String
    let windowSecs: Int64
    let cap: Int64
    let used: Int64
    let warnPercent: Int64
    let exhausted: Bool
    var id: String { "\(unit)-\(windowSecs)" }
    var share: Double { cap > 0 ? Double(used) / Double(cap) : 0 }
    enum Standing: Equatable { case fine, warning, reached }
    var standing: Standing {
        exhausted || used >= cap ? .reached : share * 100 >= Double(warnPercent) ? .warning : .fine
    }
}

/// What `PUT /accounts/{id}/limits` takes: a new limit, or new numbers for the one with this unit and window.
struct LimitDraft: Equatable, Sendable {
    var unit: String
    var windowSecs: Int64
    var cap: Int64
    var warnPercent: Int64
}

enum UsageLimitWords {
    static let windows: [(secs: Int64, title: String)] = [
        (18_000, "Every 5 hours"), (86_400, "Every day"), (604_800, "Every week"), (2_592_000, "Every 30 days"),
    ]

    static func window(_ secs: Int64) -> String {
        if let w = windows.first(where: { $0.secs == secs }) { return w.title }
        if secs % 86_400 == 0 { return "Every \(secs / 86_400) days" }
        if secs % 3_600 == 0 { return "Every \(secs / 3_600) hours" }
        if secs % 60 == 0 { return "Every \(secs / 60) minutes" }
        return "Every \(secs) seconds"
    }

    static func amount(_ n: Int64, unit: String) -> String {
        unit == "messages"
            ? coreUnit(AccountsNumbers.amount(n), n == 1 ? "message" : "messages") : AccountsNumbers.tokens(n)
    }

    static func standing(_ l: LimitItem) -> String {
        switch l.standing {
        case .reached: "Limit reached. New work waits until the window moves on."
        case .warning: "Close to the limit"
        case .fine: "Within the limit"
        }
    }

    /// A whole number of at least 1, commas and spaces allowed.
    static func parseCap(_ text: String) -> Int64? {
        AccountsNumbers.parseWhole(text).flatMap { $0 >= 1 ? $0 : nil }
    }
}

extension AccountsModel {
    func reloadLimits() async {
        guard let service else { return }
        if usage.isEmpty { limitsLoad = .loading }
        do {
            usage = try await service.usage()
            limitsLoad = .ready
        } catch { limitsLoad = state(for: error) }
    }

    func limits(of a: AccountItem) -> [LimitItem] {
        (usage.first { $0.accountID == a.id }?.limits ?? []).sorted {
            ($0.unit, $0.windowSecs) < ($1.unit, $1.windowSecs)
        }
    }

    func setLimit(_ a: AccountItem, _ d: LimitDraft) async -> Bool {
        let ok = await write(
            "limit-\(a.id)",
            reason:
                "Limit \(title(a)) to \(UsageLimitWords.amount(d.cap, unit: d.unit)), \(UsageLimitWords.window(d.windowSecs).lowercased()).",
            done: "\(title(a)): usage limit saved", keepsEdit: true
        ) { try await $0.setLimit(account: a.id, d) }
        if ok { await reloadLimits() }
        return ok
    }

    func clearLimit(_ a: AccountItem, _ l: LimitItem) async -> Bool {
        let ok = await write(
            "limit-\(a.id)",
            reason: "Remove the \(UsageLimitWords.amount(l.cap, unit: l.unit)) limit of \(title(a)).",
            done: "\(title(a)): usage limit removed"
        ) { try await $0.clearLimit(account: a.id, unit: l.unit, windowSecs: l.windowSecs) }
        if ok { await reloadLimits() }
        return ok
    }
}

extension AccountDialogs {
    static func openLimit(_ m: AccountsModel, _ a: AccountItem, editing: LimitItem?) {
        present(m, "account-limit") { close in LimitDialog(model: m, account: a, editing: editing, close: close) }
    }
    static func openClearLimit(_ m: AccountsModel, _ a: AccountItem, _ l: LimitItem) {
        present(m, "account-limit-clear") { close in ClearLimitDialog(model: m, account: a, limit: l, close: close) }
    }
}

/// Add a usage limit, or change one: unit, window, the cap and where the warning starts (5% steps).
struct LimitDialog: View {
    let model: AccountsModel
    let account: AccountItem
    let editing: LimitItem?
    let close: () -> Void
    @State private var unit: String
    @State private var window: Int64
    @State private var cap: String
    @State private var warn: Double
    @State private var busy = false

    init(model: AccountsModel, account: AccountItem, editing: LimitItem?, close: @escaping () -> Void) {
        self.model = model
        self.account = account
        self.editing = editing
        self.close = close
        _unit = State(initialValue: editing?.unit ?? "tokens")
        _window = State(initialValue: editing?.windowSecs ?? 86_400)
        _cap = State(initialValue: editing.map { AccountsNumbers.grouped($0.cap) } ?? "")
        _warn = State(initialValue: Double(editing?.warnPercent ?? 80) / 100)
    }

    private var parsed: Int64? { UsageLimitWords.parseCap(cap) }
    private var issue: String? { parsed == nil ? "A whole number, at least 1." : nil }
    private var replaces: Bool {
        editing == nil && model.limits(of: account).contains { $0.unit == unit && $0.windowSecs == window }
    }
    private var windowOptions: [CoreSelectOption<Int64>] {
        var all = UsageLimitWords.windows.map { CoreSelectOption($0.secs, $0.title) }
        if !all.contains(where: { $0.value == window }) {
            all.append(CoreSelectOption(window, UsageLimitWords.window(window)))
        }
        return all
    }

    var body: some View {
        CoreDialogPanel(
            editing == nil
                ? "Add a usage limit: \(model.title(account))" : "Change a usage limit: \(model.title(account))",
            width: Space.s8 * 15
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreFieldLabel("Counts")
                CoreSegmented(
                    "Counts",
                    segments: [CoreSegment("tokens", "Tokens"), CoreSegment("messages", "Messages")],
                    selection: $unit
                )
                .disabled(editing != nil)
                CoreSelect("How often it starts over", selection: $window, options: windowOptions)
                    .disabled(editing != nil)
                CoreTextField(
                    "Most it may use", placeholder: "For example 5000000", text: $cap,
                    error: cap.isEmpty ? nil : issue, suffix: unit, autofocus: true
                ) { go() }
                CoreFieldLabel("Warn me at")
                GlassSlider(value: $warn, in: 0.05...1, low: "Early", high: "Last moment")
                Text(
                    replaces
                        ? "This account already has this limit. Saving replaces its numbers."
                        : "Past the limit, new work on this account waits until the window moves on."
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if let e = model.writeError["limit-\(account.id)"] { AccIssue(text: e) }
                AccNotice(notice: model.host.elevationNotice)
                AccDialogButtons(confirm: "Save", busy: busy, enabled: parsed != nil, cancel: close) { go() }
            }
        }
        .accessibilityIdentifier("account-limit")
    }

    private func go() {
        guard let n = parsed else { return }
        busy = true
        let draft = LimitDraft(unit: unit, windowSecs: window, cap: n, warnPercent: Int64((warn * 100).rounded()))
        Task {
            let ok = await model.setLimit(account, draft)
            busy = false
            if ok { close() }
        }
    }
}

struct ClearLimitDialog: View {
    let model: AccountsModel
    let account: AccountItem
    let limit: LimitItem
    let close: () -> Void
    @State private var busy = false
    var body: some View {
        CoreDialogPanel("Remove this usage limit?", width: Space.s8 * 14) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(
                    "\(model.title(account)) will no longer stop at \(UsageLimitWords.amount(limit.cap, unit: limit.unit)) \(UsageLimitWords.window(limit.windowSecs).lowercased())."
                )
                .fixedSize(horizontal: false, vertical: true)
                if let e = model.writeError["limit-\(account.id)"] { AccIssue(text: e) }
                AccNotice(notice: model.host.elevationNotice)
                AccDialogButtons(confirm: "Remove limit", danger: true, busy: busy, cancel: close) {
                    busy = true
                    Task {
                        let ok = await model.clearLimit(account, limit)
                        busy = false
                        if ok { close() }
                    }
                }
            }
        }
        .accessibilityIdentifier("account-limit-clear")
    }
}

/// One row of the Limits card: its kind, the rule in a sentence and the way to change it.
struct LimitRow: View {
    let kind: String
    let title: String
    let detail: String?
    let change: String
    let action: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: Space.s2) {
            AccChip(text: kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).coreFont(size: MacTextSize.headline, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
            }
            Spacer(minLength: Space.s2)
            AccLink(title: change, symbol: "slider.horizontal.3", action: action)
        }
        .padding(Space.s2)
        .background(GlassInk.well, in: coreShape(Radius.control))
        .accessibilityElement(children: .contain)
    }
}

enum AccountBudgetLine {
    /// "Up to 2 million tokens and $50.00 each month, 40% used".
    static func text(_ b: BudgetItem) -> String {
        var caps: [String] = []
        if b.tokenCap > 0 { caps.append(AccountsNumbers.tokens(b.tokenCap)) }
        if let u = b.usdCap { caps.append(AccountsNumbers.usd(u)) }
        let per =
            switch b.period {
            case "day": "each day"
            case "week": "each week"
            case "month": "each month"
            default: "in total"
            }
        let pct = Int((b.share * 100).rounded())
        return "Up to \(caps.isEmpty ? "no amount" : caps.joined(separator: " and ")) \(per), \(pct)% used"
    }
}
