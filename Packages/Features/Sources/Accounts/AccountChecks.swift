import CoreKit
import CoreUI
import SwiftUI

/// Testing an account's key (`POST /accounts/{id}/test`, admin, nothing spent) and what one session may spend on it
/// (`PUT /accounts/{id}/session-limits`, Touch ID).
extension AccountsModel {
    func test(_ a: AccountItem) async {
        guard let service, testing == nil, mayWrite() else { return }
        testing = a.id
        testNote[a.id] = nil
        defer { testing = nil }
        do {
            let t = try await service.test(account: a.id)
            await reload()
            host.shell.showToast("\(a.label): \(TestWords.of(t.result).title.lowercased())")
        } catch {
            let code = CoreError.unwrapping(error).map(Self.code)
            if code == "runner_failed" { await reload() }
            testNote[a.id] =
                switch code {
                case "rate_limited": "It was tested less than a minute ago. Try again in a minute."
                case "no_runner": "No runner is online to test it. Start a runner that offers this provider."
                case "runner_failed": "The runner didn't answer the test, so it counts as failed."
                default: words(error)
                }
        }
    }

    func setLimits(_ a: AccountItem, tokens: Int64?, usdMicros: Int64?) async -> Bool {
        await write(
            "limits-\(a.id)", reason: "Change what one session may spend on \(a.label).",
            done: "\(a.label): \(LimitWords.tokens(tokens)), \(LimitWords.usd(usdMicros))", keepsEdit: true
        ) { try await $0.setSessionLimits(account: a.id, maxTokens: tokens, maxUSDMicros: usdMicros) }
    }
}

/// A test's status class in words. Never the provider's own text: Core keeps none.
enum TestWords {
    static func of(_ r: String) -> (title: String, line: String, hue: Color, symbol: String) {
        switch r {
        case "ok": ("Works", "The provider took the key.", GlassInk.green, "checkmark.seal.fill")
        case "rate_limited":
            ("Works, but busy", "The key is fine; the provider asked to slow down.", GlassInk.orange, "tortoise.fill")
        case "quota":
            (
                "Out of credit", "The key is fine but its plan has run out.", GlassInk.red,
                "creditcard.trianglebadge.exclamationmark"
            )
        case "auth_failed": ("Key refused", "The provider said no to this key.", GlassInk.red, "key.slash")
        case "server_error":
            ("Provider error", "The provider failed. Try again later.", GlassInk.orange, "exclamationmark.icloud")
        case "unreachable":
            ("Couldn't reach it", "The runner could not reach the provider.", GlassInk.orange, "wifi.slash")
        case "refused_address":
            ("Address refused", "Core won't send a key to that address.", GlassInk.red, "hand.raised.fill")
        case "tls_failed": ("Not secure", "The provider's secure connection failed.", GlassInk.red, "lock.slash")
        case "inconclusive":
            (
                "Can't tell", "This provider has no way to test a key, so nothing was sent.", GlassInk.slate,
                "questionmark.circle"
            )
        case "failed": ("Runner didn't answer", "The test didn't run to the end.", GlassInk.orange, "server.rack")
        default: (r, "Core reported this result.", GlassInk.slate, "questionmark.circle")
        }
    }
}

enum LimitWords {
    static func tokens(_ n: Int64?) -> String {
        n.map { "\($0.formatted(.number.notation(.compactName))) tokens" } ?? "no token limit"
    }
    static func usd(_ micros: Int64?) -> String {
        micros.map { ModelPriceItem.usd($0) } ?? "no dollar limit"
    }
}

/// The key test tile: the last answer, when, and Test now (resting for a minute after each test).
struct TestTile: View {
    let model: AccountsModel
    let account: AccountItem
    let hue: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let last = account.lastTest
            let rest = last.map { max(0, 60 - Int(ctx.date.timeIntervalSince($0.at))) } ?? 0
            let running = model.testing == account.id
            let w = last.map { TestWords.of($0.result) }
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: running ? "arrow.triangle.2.circlepath" : w?.symbol ?? "checkmark.shield")
                        .font(.system(size: 22, weight: .semibold)).foregroundStyle(
                            running ? hue : w?.hue ?? GlassInk.slate
                        )
                        .symbolEffect(.pulse, options: .repeating, isActive: running)
                        .contentTransition(.symbolEffect(.replace))
                    Text(running ? "Testing…" : w?.title ?? "Never tested")
                        .font(.system(size: MacTextSize.title, weight: .semibold))
                        .foregroundStyle(running ? GlassInk.primary : w?.hue ?? GlassInk.primary)
                    Spacer(minLength: 0)
                    AccLink(
                        title: rest > 0 ? "Again in \(rest) s" : "Test now · V", symbol: "play.fill"
                    ) { Task { await model.test(account) } }
                    .disabled(model.readOnly || running || rest > 0)
                    .help("Sends one free request with the key through a runner. Nothing is spent.")
                }
                if running {
                    CoreBusyBar()
                } else {
                    Text(w?.line ?? "One free request checks the key works. Nothing is spent.")
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note = model.testNote[account.id] {
                    AccIssue(text: note)
                } else if let last {
                    Text(
                        ctx.date.timeIntervalSince(last.at) < 60
                            ? "Tested just now"
                            : "Tested \(AccountsWords.duration(ctx.date.timeIntervalSince(last.at))) ago"
                    )
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                    .help("result \(last.result)")
                }
            }
            .animation(.smooth(duration: 0.3), value: running)
        }
    }
}

/// What one session may spend: tokens and dollars, each a big number or "No limit".
struct LimitsTileBody: View {
    let model: AccountsModel
    let account: AccountItem
    let hue: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
            figure(account.maxTokens.map { $0.formatted(.number.notation(.compactName)) }, "tokens")
            figure(account.maxUSDMicros.map { ModelPriceItem.usd($0) }, "dollars")
            Spacer(minLength: 0)
            AccLink(title: "Change · S", symbol: "slider.horizontal.3") { AccountDialogs.openLimits(model, account) }
                .disabled(model.readOnly)
        }
        Text("When a session reaches either, Core stops it.").font(.system(size: MacTextSize.meta))
            .foregroundStyle(GlassInk.secondary)
    }

    private func figure(_ v: String?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v ?? "∞").font(.system(size: 26, weight: .bold, design: .rounded)).contentTransition(.numericText())
            Text(v == nil ? "no \(unit == "tokens" ? "token" : "dollar") limit" : unit)
                .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
        }
    }
}

/// Max tokens and max dollars for one session. Empty is no limit.
struct LimitsDialog: View {
    let model: AccountsModel
    let account: AccountItem
    let close: () -> Void
    @State private var tokens: String
    @State private var dollars: String
    @State private var busy = false
    static let minTokens: Int64 = 328_000

    init(model: AccountsModel, account: AccountItem, close: @escaping () -> Void) {
        self.model = model
        self.account = account
        self.close = close
        _tokens = State(initialValue: account.maxTokens.map(String.init) ?? "")
        _dollars = State(
            initialValue: account.maxUSDMicros.map { String(format: "%.2f", Double($0) / 1_000_000) } ?? "")
    }

    private static func clean(_ s: String) -> String {
        s.filter { !",_ $".contains($0) }
    }
    private var tokenValue: Int64?? {
        let t = Self.clean(tokens)
        if t.isEmpty { return .some(nil) }
        guard let n = Int64(t), n >= Self.minTokens else { return nil }
        return .some(n)
    }
    private var usdValue: Int64?? {
        let t = Self.clean(dollars)
        if t.isEmpty { return .some(nil) }
        guard let d = Double(t), d > 0, d < 1_000_000 else { return nil }
        return .some(Int64((d * 1_000_000).rounded()))
    }

    var body: some View {
        CoreDialogPanel("Each session: \(account.label)", width: Space.s8 * 16) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: Space.s3) {
                    CoreTextField(
                        "Most tokens", placeholder: "No limit", text: $tokens,
                        error: tokenValue == nil
                            ? "A whole number, at least \(Self.minTokens.formatted()). One turn needs that much." : nil,
                        suffix: "tokens", autofocus: true
                    ) { go() }
                    CoreTextField(
                        "Most dollars", placeholder: "No limit", text: $dollars,
                        error: usdValue == nil ? "An amount in dollars, like 5 or 2.50." : nil, suffix: "USD"
                    ) { go() }
                }
                Text(
                    "A lower limit starts with the next session, resume or top-up. Sessions running now keep the limit they started with."
                )
                .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if let e = model.writeError["limits-\(account.id)"] { AccIssue(text: e) }
                AccNotice(notice: model.host.elevationNotice)
                AccDialogButtons(
                    confirm: "Save", busy: busy, enabled: tokenValue != nil && usdValue != nil, cancel: close
                ) { go() }
            }
        }
        .accessibilityIdentifier("account-limits")
    }

    private func go() {
        guard let t = tokenValue, let u = usdValue else { return }
        busy = true
        Task {
            let ok = await model.setLimits(account, tokens: t, usdMicros: u)
            busy = false
            if ok { close() }
        }
    }
}
