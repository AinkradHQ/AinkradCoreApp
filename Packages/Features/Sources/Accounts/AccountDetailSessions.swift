import CoreUI
import SwiftUI

/// What runs on the account now: its at-once slots, the live sessions (or where they went), and the per-session limit.
struct UsingNowCard: View {
    let model: AccountsModel
    let account: AccountItem
    @Environment(\.corePalette) private var palette

    var body: some View {
        let state = model.detailState(account)
        let sessions = model.detailData[account.id]?.sessions ?? []
        let live = state == .ready ? sessions.filter(\.live) : []
        let count = state == .ready ? Int(account.live ?? Int64(live.count)) : 0
        let cap = max(Int(account.cap), 1)
        DetailCard(title: "Using it now") {
            HStack(spacing: Space.s2) {
                HStack(spacing: Space.s1) {
                    ForEach(0..<min(cap, 8), id: \.self) { k in
                        coreShape(2).fill(k < count ? palette.success : palette.track).frame(width: 22, height: 8)
                    }
                }
                .animation(Motion.out(Motion.ui), value: count)
                Text("\(count) of \(cap) at once").monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        } content: {
            if live.isEmpty {
                Label(emptyLine(state, sessions), systemImage: state == .off ? "power" : "arrow.right")
                    .foregroundStyle(GlassInk.secondary).frame(minHeight: Space.s8 + Space.s2, alignment: .leading)
                    .detailSwap(state)
            } else {
                VStack(spacing: 2) {
                    ForEach(live) { SessionRowView(session: $0, plan: account.isPlan, now: model.now()) }
                }
                .padding(.horizontal, -Space.s2)
            }
            HStack(spacing: Space.s3) {
                Text(limitWords)
                DetailLinkButton(title: "Limits…", key: "l", keycap: "⌘L") { AccountDialogs.openLimits(model, account) }
                    .disabled(model.readOnly)
            }
            .coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
        }
    }

    private var limitWords: String {
        switch (account.maxTokens, account.maxUSDMicros) {
        case (nil, nil): "No limit per session"
        case (let t?, nil): "Up to \(AccountsNumbers.tokens(t)) per session"
        case (nil, let u?): "Up to \(AccountsNumbers.usd(u)) per session"
        case (let t?, let u?): "Up to \(AccountsNumbers.tokens(t)) or \(AccountsNumbers.usd(u)) per session"
        }
    }

    private func emptyLine(_ state: DetailState, _ sessions: [AccountSessionItem]) -> String {
        if state == .off { return "Nothing runs on it while it is off." }
        if state == .full || state == .signedOut {
            let moved = sessions.filter(\.moved)
            let to = model.laneRows.first { $0.chip == .inUse && $0.account.id != account.id }?.title
            if let last = moved.compactMap(\.endedAt).max(), let to {
                let n = moved.count
                return
                    "\(n == 1 ? "1 session" : "\(n) sessions") moved to \(to) at \(DetailFacts.clock(last)). They go on there."
            }
            return to.map { "New work goes to \($0) for now." } ?? "New work waits for now."
        }
        return "Nothing runs on it right now."
    }
}

/// The account's latest finished sessions, with the way to the Ledger.
struct LatestSessionsCard: View {
    let model: AccountsModel
    let account: AccountItem

    var body: some View {
        let data = model.detailData[account.id]
        let state = model.detailState(account)
        let done = (data?.sessions ?? []).filter { !$0.live || state != .ready }.prefix(4)
        DetailCard(title: "Latest sessions") {
            DetailLinkButton(title: "Open Ledger", key: "j", keycap: "⌘J") { model.go(.ledger) }
        } content: {
            if done.isEmpty {
                Text(data == nil ? "Reading its sessions…" : "No session has used it yet.")
                    .foregroundStyle(GlassInk.secondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(done)) {
                        SessionRowView(session: $0, plan: account.isPlan, now: model.now(), ended: true)
                    }
                }
                .padding(.horizontal, -Space.s2)
            }
            Spacer(minLength: 0)
        }
    }
}

/// One session: its title, the model (a plan's default reads "Claude's default", never "unknown") and runner, and what it
/// used: tokens for a plan, dollars and tokens for a key.
struct SessionRowView: View {
    let session: AccountSessionItem
    let plan: Bool
    let now: Date
    var ended = false
    @State private var hovering = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        let s = session
        HStack(spacing: Space.s3) {
            IconTile("sparkles", hue: GlassInk.slate, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title ?? "Untitled session").coreFont(size: MacTextSize.body, weight: .medium).lineLimit(1)
                    .help(s.title ?? "")
                HStack(spacing: Space.s2) {
                    if s.live && !ended {
                        coreShape(2).fill(palette.success).frame(width: 6, height: 6).help("Running now")
                    }
                    Text(s.model.map(ModelNames.short) ?? (plan ? "Claude's default" : "Its default model"))
                        .coreFont(size: MacTextSize.meta, weight: .medium)
                        .foregroundStyle(s.model == nil ? GlassInk.secondary : GlassInk.primary)
                        .padding(.horizontal, Space.s1 + 1).frame(minHeight: 17)
                        .background(s.model == nil ? GlassInk.well : GlassInk.wellHover, in: coreShape(4))
                    if let r = s.runnerName { Text("on \(r)").lineLimit(1) }
                }
                .coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 2) {
                Text(s.usdMicros.map(AccountsNumbers.usd) ?? DetailFacts.compact(s.tokens))
                    .coreFont(size: MacTextSize.body, weight: .semibold)
                Text("\(s.usdMicros == nil ? "" : "\(DetailFacts.compact(s.tokens)) ")tokens · \(when)")
                    .coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
            }
            .monospacedDigit().lineLimit(1)
        }
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s2 - 1)
        .background(hovering ? GlassInk.well : .clear, in: coreShape(Radius.control))
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.press), value: hovering)
        .accessibilityElement(children: .combine)
    }

    private var when: String {
        let at = ended ? (session.endedAt ?? session.startedAt) : session.startedAt
        let s = now.timeIntervalSince(at)
        if s < 60 { return "now" }
        if s < 86_400 { return "\(AccountsWords.duration(s)) ago" }
        if s < 172_800 { return "yesterday" }
        return at.formatted(.dateTime.weekday(.wide))
    }
}
