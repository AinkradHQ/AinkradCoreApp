import CoreUI
import Shell
import SwiftUI

/// Settings, Security, Lockouts: who is locked out after too many failed tries, with a live countdown. One lock is the
/// cursor (↑ ↓); ⌫ clears it now (Touch ID), R reads again. Locks end by themselves.
struct LockoutsSection: View {
    let app: AppModel
    @State private var cursor: String?
    @FocusState private var focus: Bool

    var body: some View {
        let model = app.lockouts!
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(
                "Too many failed tries lock an address or a device for a while. Each new lock lasts twice as long, up to an hour."
            )
            .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            StepUpBanner(app: app)
            if app.service == nil {
                NotConnectedNote(what: "Lockouts")
            } else {
                LoadNote(state: model.load) { Task { await model.reload() } }
                if model.load == .ready { verdict(model) }
                VStack(spacing: Space.s3) {
                    ForEach(model.items) { l in
                        LockCard(model: model, lock: l, selected: cursor == l.key) {
                            cursor = l.key
                            focus = true
                        }
                        .transition(.opacity)
                    }
                }
                .animation(Motion.out(Motion.move), value: model.items.map(\.key))
                .onChange(of: model.items.map(\.key), initial: true) { _, keys in
                    if !keys.contains(cursor ?? "") { cursor = keys.first }
                }
            }
        }
        .foregroundStyle(GlassInk.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusable().focused($focus).focusEffectDisabled()
        .onKeyPress(phases: .down) { press in keys(press, model) }
        .task {
            await model.reload()
            cursor = model.items.first?.key
            focus = true
        }
    }

    private func verdict(_ model: LockoutsModel) -> some View {
        let n = model.items.count
        let hue = n == 0 ? GlassInk.green : GlassInk.orange
        return HStack(spacing: Space.s4) {
            IconTile(n == 0 ? "lock.open.fill" : "lock.fill", hue: hue, size: 56, bounce: n)
            VStack(alignment: .leading, spacing: 3) {
                Text(n == 0 ? "Nothing is locked" : n == 1 ? "1 lock right now" : "\(n) locks right now")
                    .font(.system(size: MacTextSize.large, weight: .semibold)).foregroundStyle(hue)
                    .contentTransition(.numericText())
                Text(
                    n == 0
                        ? "Everyone can sign in and ask for Touch ID."
                        : "Each ends by itself when its time runs out. Clear one to end it now."
                )
                .foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s3)
            AppActionTile(title: "Read now", symbol: "arrow.clockwise", key: "⌘R", hue: GlassInk.blue) {
                Task { await model.reload() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(Space.s4)
        .coreWell()
        .animation(Motion.out(Motion.move), value: n)
    }

    private func keys(_ press: KeyPress, _ model: LockoutsModel) -> KeyPress.Result {
        let list = model.items
        let at = list.firstIndex { $0.key == cursor } ?? 0
        switch press.key {
        case .downArrow, .upArrow:
            let i = at + (press.key == .downArrow ? 1 : -1)
            if list.indices.contains(i) { withAnimation(Motion.out(Motion.ui)) { cursor = list[i].key } }
            return .handled
        case .delete, .deleteForward:
            if list.indices.contains(at) { Task { await model.clear(list[at]) } }
            return .handled
        default:
            guard press.characters.lowercased() == "r", press.modifiers.isEmpty else { return .ignored }
            Task { await model.reload() }
            return .handled
        }
    }
}

/// One lock: what is locked in plain words, a big live countdown with a bar that shrinks (orange, red in the last minute),
/// the strikes so far, and Clear at the top right.
private struct LockCard: View {
    let model: LockoutsModel
    let lock: LockoutInfo
    let selected: Bool
    let pick: () -> Void
    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int(lock.lockedUntil.timeIntervalSince(ctx.date).rounded(.up)))
            let soon = left > 0 && left <= 60
            let hue = left == 0 ? GlassInk.green : soon ? GlassInk.red : GlassInk.orange
            let who = Self.who(lock.key)
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s3) {
                    IconTile(left == 0 ? "lock.open.fill" : who.symbol, hue: hue, size: 40, bounce: left == 0)
                    VStack(alignment: .leading, spacing: Space.s1 / 2) {
                        Text(who.title).font(.system(size: MacTextSize.headline, weight: .semibold))
                        Text(who.sub).foregroundStyle(GlassInk.secondary)
                    }
                    Spacer(minLength: Space.s3)
                    Text(left == 0 ? "Ended" : Countdown.text(left))
                        .font(.system(size: MacTextSize.large, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(hue).contentTransition(.numericText(countsDown: true))
                    AppActionTile(
                        title: "Clear", symbol: "lock.open", key: selected ? "⌫" : "", hue: GlassInk.blue,
                        prominent: selected
                    ) { Task { await model.clear(lock) } }
                    .disabled(left == 0)
                    .opacity(left == 0 ? 0.4 : 1)
                    .help("End this lock now. Asks for Touch ID.")
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        coreShape(3).fill(GlassInk.track.opacity(0.6))
                        coreShape(3)
                            .fill(
                                LinearGradient(
                                    colors: [hue.opacity(0.5), hue], startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: g.size.width * Double(left) / LockMeter.total(left))
                    }
                }
                .frame(height: 6)
                .animation(.linear(duration: 1), value: left)
                HStack(spacing: Space.s2) {
                    HStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { i in
                            coreShape(2).fill(i < lock.strikes ? hue : GlassInk.track).frame(width: 14, height: 6)
                        }
                    }
                    .help("\(lock.strikes) failed \(lock.strikes == 1 ? "lock" : "locks") in a row")
                    Text(
                        "Strike \(lock.strikes). Until \(lock.lockedUntil.formatted(date: .omitted, time: .shortened)); the next lock would last twice as long."
                    )
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                }
            }
            .padding(Space.s3)
            .coreWell(active: selected || hovering)
            .contentShape(coreShape(Radius.cardMac))
            .onTapGesture(perform: pick)
            .onHover { hovering = $0 }
            .animation(Motion.out(Motion.ui), value: selected)
            .help(lock.key)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(who.title), \(left == 0 ? "ended" : "\(Countdown.text(left)) left")")
        }
    }

    /// `ip:…`, `ipdev:…:…`, `stepup:…` in words.
    static func who(_ key: String) -> (title: String, sub: String, symbol: String) {
        let p = key.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        switch (p.first, p.count) {
        case ("ipdev", 3):
            return (p[1], "This address, on one device", "laptopcomputer.trianglebadge.exclamationmark")
        case ("ip", 2...):
            return (p.dropFirst().joined(separator: ":"), "An internet address", "network.badge.shield.half.filled")
        case ("stepup", 2...): return ("Touch ID", "On one device", "touchid")
        default: return (key, "Locked", "lock.fill")
        }
    }
}

/// The Core doubles each lock (1, 2, 4 ... 60 minutes): the bar measures what is left against the next length up from it.
enum LockMeter {
    static func total(_ left: Int) -> Double {
        var minutes = 1
        while minutes * 60 < left, minutes < 60 { minutes *= 2 }
        return Double(max(min(minutes, 60) * 60, left, 1))
    }
}
