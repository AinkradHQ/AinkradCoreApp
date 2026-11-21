import CoreUI
import SwiftUI

/// One account (approved mockup `Designs/core/0-10/review/account-details`, Ahmed 2026-11-21). The head with its one main
/// action and ⋯ (⌘.), then the AI order: what the account is to AI sessions now, and the lane of the order with the flow
/// into the account that takes new work. Under it: a plan's windows (or a key's spend), the last 7 days, what runs on it now
/// and its latest sessions. Pools never show: each entry of the AI order is a pool of one account, an internal of the Core.
struct AccountDetailView: View {
    let model: AccountsModel
    let account: AccountItem
    @State private var shown = false
    /// The account whose key ending Touch ID unlocked (Settings, Accounts, Ask Touch ID to reveal keys).
    @State private var revealed: Int64?
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @Environment(\.corePalette) private var palette

    private var reduce: Bool { systemReduce || model.debugReduceMotion }

    var body: some View {
        let a = account
        let words = model.detailWords(a)
        VStack(alignment: .leading, spacing: Space.s4) {
            head(a, words)
            if let e = model.writeError["account-\(a.id)"] { AccIssue(text: e) }
            VStack(alignment: .leading, spacing: Space.s5) {
                DetailVerdict(model: model, account: a, words: words)
                DetailLane(model: model, account: a)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4).padding(.bottom, Space.s5)
            .coreWell()
            .background(tint(words.tone), in: coreShape(Radius.cardMac))
            .animation(Motion.out(Motion.move), value: words.tone)
            HStack(alignment: .top, spacing: Space.s4) {
                VStack(spacing: Space.s4) {
                    if a.isPlan {
                        PlanWindowsCard(model: model, account: a)
                    } else {
                        SpendCard(model: model, account: a)
                    }
                    WeekChart(model: model, account: a)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: Space.s4) {
                    UsingNowCard(model: model, account: a)
                    LatestSessionsCard(model: model, account: a)
                }
                .frame(maxWidth: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            if model.detailTech {
                HStack(spacing: Space.s2) {
                    AccChip(text: "state \(a.state)", mono: true)
                    if !a.baseURL.isEmpty { AccChip(text: a.baseURL, mono: true) }
                    AccChip(text: "id \(a.id)", mono: true)
                    AccChip(text: "added \(a.createdAt.formatted(date: .abbreviated, time: .shortened))")
                }
                .transition(.opacity)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .environment(\.detailReduce, reduce)
        .environment(\.detailShown, shown)
        .background { DetailKeys(model: model, account: a) }
        .task(id: "\(a.id)-\(model.serviceEpoch)") {
            shown = false
            async let costs: Void = model.reloadCosts()
            async let watch: Void = model.watchDetail(a.id)
            try? await Task.sleep(for: .milliseconds(60))
            shown = true
            _ = await (costs, watch)
        }
        .onDisappear { model.detailMore = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account-detail")
    }

    private func tint(_ tone: Tone) -> Color {
        switch tone {
        case .warn: palette.warning.opacity(0.08)
        case .fail: palette.error.opacity(0.08)
        default: .clear
        }
    }

    // MARK: head

    private func head(_ a: AccountItem, _ words: DetailWords) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            BackTile { _ = AccountsKeys.back(model) }.help("Back to Accounts (esc)")
            AccTile(large: true, provider: a.provider)
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(spacing: Space.s3) {
                    Text(model.title(a)).coreFont(size: MacTextSize.large + 2, weight: .bold).lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    StateBadge(words.chip, tone: words.tone, symbol: words.symbol).detailSwap(words.chip)
                }
                subline(a)
            }
            Spacer(minLength: Space.s3)
            DetailActions(model: model, account: a)
        }
    }

    private func subline(_ a: AccountItem) -> some View {
        HStack(spacing: Space.s2) {
            Text(model.kindName(a))
            if a.isPlan {
                Text("·").foregroundStyle(GlassInk.secondary.opacity(0.6))
                Text(
                    model.detailState(a) == .signedOut
                        ? "signed out\(a.lastTest.map { " at \(DetailFacts.clock($0.at))" } ?? "")"
                        : "signed in on \(a.createdAt.formatted(.dateTime.day().month(.abbreviated)))")
            } else {
                if !a.maskedTail.isEmpty { tail(a) }
                Text("·").foregroundStyle(GlassInk.secondary.opacity(0.6))
                Text("added \(a.createdAt.formatted(.dateTime.day().month(.abbreviated)))")
            }
            if let b = a.runnerBinding { RunnerBoundNote(binding: b) }
        }
        .foregroundStyle(GlassInk.secondary)
        .lineLimit(1)
    }

    /// "ends 7Qx2" on a small well; held back behind Touch ID when Settings asks for it.
    @ViewBuilder private func tail(_ a: AccountItem) -> some View {
        let hidden = AccountsOptions.asksTouchID && revealed != a.id
        let label = Label(hidden ? "ends ••••" : "ends \(a.maskedTail)", systemImage: "key")
            .coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.primary).monospacedDigit()
            .padding(.horizontal, Space.s2 - 1).frame(minHeight: 20)
            .background(GlassInk.well, in: coreShape(Radius.chip))
        if hidden {
            Button {
                Task {
                    do {
                        try await model.host.elevated("Show how this key ends.", done: "shown", keepsEdit: false) {}
                        revealed = a.id
                    } catch {}
                }
            } label: {
                label
            }
            .buttonStyle(.plain).help("Show how this key ends. Needs Touch ID")
        } else {
            label
        }
    }
}

/// The verdict at the top of the order card, or the check while it runs: three steps that fill on their own clock (the
/// last holds until Claude answers), then a drawn check mark and how long it took.
struct DetailVerdict: View {
    let model: AccountsModel
    let account: AccountItem
    let words: DetailWords
    @State private var started: Date?
    @State private var finished = false
    @Environment(\.corePalette) private var palette
    @Environment(\.coreAccent) private var accent
    @Environment(\.detailReduce) private var reduce

    static let steps: [(String, String, Double)] = [
        ("Lend the sign-in to a runner", "cpu", 1.1), ("Send one short message", "paperplane", 1.6),
        ("Read the answer", "text.alignleft", 0.9),
    ]

    private var busy: Bool { model.checking == account.id || model.testing == account.id }

    var body: some View {
        Group {
            if busy {
                running
            } else if finished, let r = result {
                row(symbol: nil, tone: r.ok ? .run : .fail, title: r.title, line: r.line, right: "Checked just now")
            } else {
                row(symbol: words.symbol, tone: words.tone, title: words.title, line: words.line, right: rightWords)
            }
        }
        .detailSwap("\(busy)-\(finished)-\(words.title)")
        .onChange(of: busy) { _, now in
            if now {
                started = Date()
                finished = false
            } else if started != nil {
                finished = true
                if let r = result, r.ok { model.host.shell.showToast("\(model.title(account)) works\(r.short)") }
            }
        }
        .onChange(of: account.id) { _, _ in finished = false }
    }

    private func row(symbol: String?, tone: Tone, title: String, line: String, right: String?) -> some View {
        HStack(spacing: Space.s4) {
            ZStack {
                if let symbol {
                    Image(systemName: symbol).coreFont(size: MacTextSize.title, weight: .semibold)
                } else {
                    DrawnCheck()
                }
            }
            .foregroundStyle(palette.tone(tone).ink)
            .frame(width: 40, height: 40)
            .background(palette.tone(tone).ink.opacity(0.14), in: coreShape(Radius.cardMac))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).coreFont(size: MacTextSize.title + 1, weight: .semibold)
                Text(line).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            if let right { Text(right).coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary) }
        }
        .accessibilityElement(children: .combine)
    }

    private var running: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { tl in
            let el = tl.date.timeIntervalSince(started ?? tl.date)
            let total = Self.steps.reduce(0) { $0 + $1.2 }
            HStack(spacing: Space.s4) {
                Image(systemName: "arrow.clockwise").coreFont(size: MacTextSize.title, weight: .semibold)
                    .foregroundStyle(GlassInk.accentInk(accent))
                    .frame(width: 40, height: 40)
                    .background(GlassInk.accent(accent).opacity(0.18), in: coreShape(Radius.cardMac))
                HStack(spacing: Space.s2) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { k, s in
                        let before = Self.steps.prefix(k).reduce(0) { $0 + $1.2 }
                        // The last step never completes on the clock: it waits for the answer.
                        let p = min(k == Self.steps.count - 1 ? 0.92 : 1, max(0, (el - before) / s.2))
                        step(p, s.0 == Self.steps[0].0 ? (account.isPlan ? s.0 : "Lend the key to a runner") : s.0, s.1)
                    }
                }
                Text(el < total ? "about \(max(1, Int((total - el).rounded(.up)))) s left" : "waiting for the answer")
                    .coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary).monospacedDigit()
                    .frame(minWidth: 150, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Checking \(model.title(account))")
    }

    private func step(_ p: Double, _ label: String, _ symbol: String) -> some View {
        let done = p >= 1
        return VStack(alignment: .leading, spacing: Space.s2) {
            DetailBar(value: p, height: 6, tint: done ? palette.success.opacity(0.8) : nil)
            Label(label, systemImage: done ? "checkmark" : symbol)
                .coreFont(size: MacTextSize.meta + 1, weight: .medium)
                .foregroundStyle(done ? GlassInk.secondary : p > 0 ? GlassInk.primary : GlassInk.secondary.opacity(0.6))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rightWords: String? {
        let state = model.detailState(account)
        guard state == .ready || state == .problem else { return nil }
        let now = model.now()
        func ago(_ d: Date) -> String {
            let s = now.timeIntervalSince(d)
            return s < 60
                ? "just now"
                : s < 86_400
                    ? "\(AccountsWords.duration(s)) ago" : "on \(d.formatted(.dateTime.day().month(.abbreviated)))"
        }
        if account.isPlan {
            if let c = model.detailData[account.id]?.lastCheck {
                return "Checked \(ago(c.at)) · \(c.ok ? "works" : "failed")"
            }
            if let c = model.planChecks[account.id] {
                return "Checked \(ago(c.at)) · \(PlanCheckWords.of(c.check.result).ok ? "works" : "failed")"
            }
            return nil
        }
        return account.lastTest.map {
            "Checked \(ago($0.at)) · \($0.result == "ok" ? "key works" : TestWords.of($0.result).title.lowercased())"
        }
    }

    /// The answer of the check that just ran: words for the row, and the toast's tail.
    private var result: (ok: Bool, title: String, line: String, short: String)? {
        if account.isPlan {
            guard let c = model.planChecks[account.id]?.check else {
                return model.checkNote[account.id].map { (false, "The check failed", $0, "") }
            }
            let w = PlanCheckWords.of(c.result)
            guard w.ok else { return (false, w.title, w.line, "") }
            let secs = c.latencyMs.map { " in \(Self.seconds($0))" } ?? ""
            let on = c.runner.map { " on \($0)" } ?? ""
            return (
                true, "It works", "Claude answered\(secs)\(on). It used a little of the 5-hour window, no money.",
                c.latencyMs.map { " · answered in \(Self.seconds($0))" } ?? ""
            )
        }
        if let note = model.testNote[account.id] { return (false, "The check failed", note, "") }
        guard let t = account.lastTest else { return nil }
        let w = TestWords.of(t.result)
        return t.result == "ok" ? (true, "It works", "\(w.line) Nothing was spent.", "") : (false, w.title, w.line, "")
    }

    static func seconds(_ ms: Int64) -> String {
        "\((Double(ms) / 1000).formatted(.number.precision(.fractionLength(1)))) s"
    }
}

/// The success check, drawn in 500 ms after 100 ms; Reduce Motion: it fades in.
private struct DrawnCheck: View {
    @State private var drawn: CGFloat = 0
    @Environment(\.detailReduce) private var reduce

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 5, y: 12.5))
            p.addLine(to: CGPoint(x: 9.5, y: 17))
            p.addLine(to: CGPoint(x: 19, y: 7))
        }
        .trim(from: 0, to: reduce ? 1 : drawn)
        .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .frame(width: 24, height: 24)
        .opacity(reduce ? drawn : 1)
        .onAppear { withAnimation(reduce ? .easeOut(duration: 0.2) : Motion.out(0.5).delay(0.1)) { drawn = 1 } }
        .accessibilityHidden(true)
    }
}
