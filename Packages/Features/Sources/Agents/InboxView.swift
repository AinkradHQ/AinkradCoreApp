import CoreUI
import SwiftUI

/// Approvals: one verdict (all clear, or how many agents wait), then each waiting request under its session (the session's
/// glyph, runner and Open session), then what was decided since this Mac opened. The first waiting card answers the keys.
struct InboxView: View {
    @Bindable var model: AgentsModel

    var body: some View {
        let pending = model.pending
        let decided = model.decided
        CoreDialogPanel("Approvals", width: Space.s8 * 22) {
            VStack(alignment: .leading, spacing: Space.s3) {
                verdict(pending.count)
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        ForEach(Array(pending.enumerated()), id: \.element.id) { i, r in
                            VStack(alignment: .leading, spacing: Space.s2) {
                                who(r)
                                ApprovalCardView(model: model, request: r, keys: i == 0)
                            }
                        }
                        if !decided.isEmpty {
                            VStack(alignment: .leading, spacing: Space.s2) {
                                Text("Answered since this Mac opened").coreFont(
                                    size: MacTextSize.headline, weight: .semibold
                                )
                                .agentHeading()
                                ForEach(decided) { r in ApprovalCardView(model: model, request: r) }
                            }
                        }
                    }
                }
                .frame(maxHeight: Space.s8 * 18)
                HStack {
                    Spacer(minLength: 0)
                    AppActionTile(title: "Done", symbol: "checkmark", key: "esc", hue: GlassInk.slate) {
                        model.shell.closeDialog()
                    }
                    .coreShortcut(.cancel)
                }
            }
            .foregroundStyle(GlassInk.primary)
        }
    }

    private var elevatedUntil: Date? { model.shell.elevatedUntil.flatMap { $0 > Date() ? $0 : nil } }

    private func verdict(_ n: Int) -> some View {
        let hue = n == 0 ? GlassInk.green : GlassInk.orange
        return HStack(spacing: Space.s4) {
            IconTile(n == 0 ? "checkmark.seal.fill" : "hand.raised.fill", hue: hue, size: 52, bounce: n)
                .shadow(color: hue.opacity(0.5), radius: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    n == 0
                        ? "Nothing is waiting on you"
                        : n == 1 ? "1 approval is waiting on you" : "\(n) approvals are waiting on you"
                )
                .coreFont(size: MacTextSize.large, weight: .bold).foregroundStyle(GlassInk.ink(hue))
                .contentTransition(.numericText())
                Label(touchNote, systemImage: elevatedUntil == nil ? "touchid" : "checkmark.shield")
                    .foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(hue.opacity(0.1), in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(hue.opacity(0.4), lineWidth: 1) }
        .animation(.smooth(duration: 0.4), value: n)
    }

    /// Words follow the elevation: before Touch ID it says it is needed, after it says until when it is not.
    private var touchNote: String {
        guard let until = elevatedUntil else {
            return "Approving needs Touch ID once; the next ones need none for a while."
        }
        return "Touch ID done: no new prompt until \(until.formatted(date: .omitted, time: .shortened))."
    }

    private func who(_ r: ApprovalRequest) -> some View {
        let s = model.sessions.session(r.session)
        let hue = SessionTile.hue(s?.harness ?? "")
        return HStack(spacing: Space.s2) {
            IconTile(AgentsModel.harnessSymbol(s?.harness ?? ""), hue: hue, size: 26)
            Text(
                "\(s.map { AgentWords.harnessName($0.harness) } ?? "An agent") on \(s.map { model.runnerName($0.runner) } ?? "a runner")"
            )
            .coreFont(size: MacTextSize.body, weight: .semibold)
            Spacer(minLength: 0)
            AppActionTile(title: "Open session", symbol: "arrow.up.right", key: "", hue: hue) {
                model.openSession(r.session)
            }
        }
    }
}

/// The account news a banner can tell an admin about, in the Core's push kinds.
private struct AccountTile {
    let kind: String, title: String, sub: String, symbol: String, onSymbol: String
    static let all = [
        AccountTile(
            kind: "account_health", title: "An account stops working", sub: "The provider keeps failing for it.",
            symbol: "exclamationmark.triangle", onSymbol: "exclamationmark.triangle.fill"),
        AccountTile(
            kind: "account_failover", title: "A session moves to another account",
            sub: "An account hit its limit and a run moved on.", symbol: "arrow.triangle.swap",
            onSymbol: "arrow.triangle.swap"),
        AccountTile(
            kind: "account_expired", title: "An account is turned off", sub: "The provider refused its key.",
            symbol: "key", onSymbol: "key.fill"),
    ]
}

/// Settings, Notifications: whether macOS lets Ainkrad show banners, what it tells you about, and where activity shows
/// inside Ainkrad. Saved on this Mac.
struct NotificationsSection: View {
    @Bindable var model: AgentsModel

    var body: some View {
        let allowed = model.notifierPermission == .allowed
        VStack(alignment: .leading, spacing: Space.s4) {
            permission
            GlassSection(
                "Tell me when", sub: "Banners show while Ainkrad is open.", symbol: "bell.badge.fill",
                hue: GlassInk.red, index: 1
            ) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Space.s3), GridItem(.flexible())], spacing: Space.s3
                ) {
                    GlassToggleTile(
                        "An approval is waiting",
                        sub: allowed ? "An agent asks to use a tool and waits for you." : "Allow banners above first.",
                        symbol: "hand.raised", onSymbol: "hand.raised.fill", isOn: $model.notifyApprovals, fill: true
                    )
                    .disabled(!allowed)
                    if model.isAdmin {
                        ForEach(AccountTile.all, id: \.kind) { t in
                            GlassToggleTile(
                                t.title, sub: allowed ? t.sub : "Allow banners above first.", symbol: t.symbol,
                                onSymbol: t.onSymbol,
                                isOn: Binding(get: { model.notifies(t.kind) }, set: { model.setNotifies(t.kind, $0) }),
                                fill: true
                            )
                            .disabled(!allowed)
                        }
                    }
                    ForEach(
                        [
                            ("A session fails", "xmark.octagon"), ("A session finishes", "checkmark.circle"),
                            ("A session stalls", "pause.circle"),
                        ],
                        id: \.0
                    ) { title, symbol in
                        GlassToggleTile(
                            title, sub: "Coming: your Core can't send this yet.", symbol: symbol,
                            isOn: .constant(false), fill: true
                        )
                        .disabled(true).opacity(0.55)
                    }
                }
                BannerPreview()
            }
            GlassSection(
                "Inside Ainkrad", sub: "What is running and what needs you.", symbol: "waveform.path.ecg",
                hue: GlassInk.blue, index: 2
            ) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Space.s3), GridItem(.flexible())], spacing: Space.s3
                ) {
                    GlassToggleTile(
                        "The bell", sub: "Always on: what waits on you, runners and recent events.", symbol: "bell",
                        onSymbol: "bell.fill", isOn: .constant(true), fill: true
                    )
                    .disabled(true)
                    GlassToggleTile(
                        "Status bar chip", sub: "“2 running · 1 waiting” next to the bell.", symbol: "capsule",
                        onSymbol: "capsule.fill",
                        isOn: Binding(
                            get: { model.shell.showActivityChip },
                            set: {
                                model.shell.showActivityChip = $0
                                model.shell.settings.saved()
                            }), fill: true)
                }
            }
        }
        .foregroundStyle(GlassInk.primary)
        .task { await model.refreshPermission() }
    }

    private var permission: some View {
        let p = model.notifierPermission
        let hue = p == .allowed ? GlassInk.green : p == .notAsked ? GlassInk.blue : GlassInk.orange
        return HStack(spacing: Space.s4) {
            IconTile(p == .allowed ? "bell.fill" : "bell.slash.fill", hue: hue, size: 56, bounce: p == .allowed)
                .shadow(color: hue.opacity(0.5), radius: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    p == .allowed
                        ? "Banners are on" : p == .notAsked ? "Banners aren't set up yet" : "macOS has banners off"
                )
                .coreFont(size: MacTextSize.large, weight: .bold).foregroundStyle(GlassInk.ink(hue))
                Text(
                    p == .allowed
                        ? "macOS shows Ainkrad's banners."
                        : p == .notAsked
                            ? "macOS asks you once. Until then Ainkrad can't show banners."
                            : "Turn them on in System Settings → Notifications → Ainkrad. Ainkrad can't change this itself."
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            if p == .notAsked {
                AppActionTile(title: "Turn on", symbol: "bell.badge", key: "↩", hue: GlassInk.blue, prominent: true) {
                    Task { await model.turnOnNotifications() }
                }
                .keyboardShortcut(.defaultAction)
            } else if p == .denied {
                AppActionTile(title: "Open System Settings", symbol: "gearshape", key: "", hue: GlassInk.slate) {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
            }
        }
        .padding(Space.s4)
        .background(hue.opacity(0.1), in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(hue.opacity(0.4), lineWidth: 1) }
        .animation(.smooth(duration: 0.35), value: p)
        .accessibilityElement(children: .contain)
    }
}

/// A picture of the macOS banner an approval produces: the real one is drawn by macOS, this is only a preview of its words.
private struct BannerPreview: View {
    @Environment(\.corePalette) private var palette
    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            AgentMark(harness: "claude")
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text("claude is waiting on you").coreFont(size: MacTextSize.headline, weight: .semibold)
                Text("It wants to use Bash on mac-studio.").foregroundStyle(palette.text2)
            }
            Spacer(minLength: 0)
            Text("now").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
        }
        .padding(Space.s3).frame(maxWidth: Space.s8 * 12, alignment: .leading)
        .background(.black.opacity(0.25), in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .help("What an approval banner looks like")
        .accessibilityElement(children: .combine).accessibilityLabel("Preview: claude is waiting on you")
    }
}
