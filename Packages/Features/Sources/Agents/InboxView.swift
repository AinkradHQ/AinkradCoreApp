import CoreUI
import SwiftUI

/// Approvals: everything agents wait on you for, newest request last, with what was decided since this Mac opened.
struct InboxView: View {
    @Bindable var model: AgentsModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let pending = model.pending
        let decided = model.decided
        CoreDialogPanel("Approvals", width: Space.s8 * 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text(
                        pending.isEmpty
                            ? "Nothing is waiting on you."
                            : "\(pending.count) \(pending.count == 1 ? "agent is" : "agents are") waiting on you."
                    )
                    .foregroundStyle(palette.text2)
                    Label(touchNote, systemImage: elevatedUntil == nil ? "lock.shield" : "checkmark.shield")
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                    if pending.isEmpty {
                        VStack(spacing: Space.s1) {
                            Text("All clear").font(.system(size: MacTextSize.headline, weight: .semibold))
                            Text("New requests from agents show up here and in the bell.").foregroundStyle(
                                palette.text2)
                        }
                        .frame(maxWidth: .infinity).padding(Space.s6)
                    }
                    ForEach(Array(pending.enumerated()), id: \.element.id) { i, r in
                        VStack(alignment: .leading, spacing: Space.s1) {
                            who(r)
                            ApprovalCardView(model: model, request: r, keys: i == 0)
                        }
                    }
                    if !decided.isEmpty {
                        Text("Decided").font(.system(size: MacTextSize.headline, weight: .semibold)).agentHeading()
                        ForEach(decided) { r in ApprovalCardView(model: model, request: r) }
                    }
                }
            }
            .frame(maxHeight: Space.s8 * 18)
            HStack {
                Spacer(minLength: 0)
                Button("Done") { model.shell.closeDialog() }.buttonStyle(.coreSecondary).coreShortcut(.cancel)
            }
        }
    }

    private var elevatedUntil: Date? { model.shell.elevatedUntil.flatMap { $0 > Date() ? $0 : nil } }

    /// Words follow the elevation: before Touch ID it says it is needed, after it says until when it is not.
    private var touchNote: String {
        guard let until = elevatedUntil else {
            return "Approving an agent action needs Touch ID. After one, the others need none for a while."
        }
        return "Touch ID done. Approvals need no new prompt until \(until.formatted(date: .omitted, time: .shortened))."
    }

    private func who(_ r: ApprovalRequest) -> some View {
        let s = model.sessions.session(r.session)
        return HStack(spacing: Space.s2) {
            Text("\(s?.harness ?? "agent") · \(s.map { model.runnerName($0.runner) } ?? "")").fontWeight(.semibold)
            Button("Open session") { model.openSession(r.session) }.buttonStyle(CoreButtonStyle(.plain, size: .small))
        }
        .font(.system(size: MacTextSize.body))
    }
}

/// Settings, Notifications: what macOS allows, and which approvals show a banner. Saved on this Mac.
struct NotificationsSection: View {
    @Bindable var model: AgentsModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("macOS permission").font(.system(size: MacTextSize.title, weight: .semibold)).agentHeading()
                Text("macOS decides whether Ainkrad may show banners. Ainkrad asks once.").foregroundStyle(
                    palette.text2)
                permission
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Notify me when").font(.system(size: MacTextSize.title, weight: .semibold)).agentHeading()
                CoreCheckbox(
                    "An approval is waiting", detail: "An agent asks to use a tool and waits for you.",
                    isOn: $model.notifyApprovals
                ).disabled(model.notifierPermission != .allowed)
                Text(
                    "Banners show while Ainkrad is open. Telling this Mac when Ainkrad is closed needs push, which the Core does not offer to this Mac yet."
                )
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                .fixedSize(horizontal: false, vertical: true)
                // Failures, finished sessions and stalls have no push channel on the Core yet: shown, never pretended.
                ForEach(["A session fails", "A session finishes", "A session stalls"], id: \.self) { kind in
                    CoreCheckbox(kind, detail: "Not available yet.", isOn: .constant(false)).disabled(true)
                }
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("What a banner looks like").font(.system(size: MacTextSize.title, weight: .semibold))
                    .agentHeading()
                BannerPreview()
            }
        }
        .task { await model.refreshPermission() }
    }

    @ViewBuilder
    private var permission: some View {
        switch model.notifierPermission {
        case .allowed:
            NoticeBanner(
                notice: InlineNotice(
                    title: "Notifications are allowed", detail: "macOS shows Ainkrad banners.", symbol: "bell",
                    tone: .run))
        case .notAsked:
            NoticeBanner(
                notice: InlineNotice(
                    title: "macOS has not been asked yet", detail: "Ainkrad cannot show banners until you allow them.",
                    symbol: "bell.slash", tone: .queue))
            Button("Ask macOS") { Task { await model.turnOnNotifications() } }.buttonStyle(.coreProminent)
        case .denied:
            NoticeBanner(
                notice: InlineNotice(
                    title: "Notifications are turned off in macOS",
                    detail:
                        "Turn them on in System Settings, Notifications, Ainkrad. Ainkrad cannot change this itself.",
                    symbol: "bell.slash"))
        }
    }
}

/// A picture of the macOS banner an approval produces: the real one is drawn by macOS, this is only a preview of its words.
private struct BannerPreview: View {
    @Environment(\.corePalette) private var palette
    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            AgentMark(harness: "claude")
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text("claude is waiting on you").font(.system(size: MacTextSize.headline, weight: .semibold))
                Text("It wants to use Bash on mac-studio.").foregroundStyle(palette.text2)
            }
            Spacer(minLength: 0)
            Text("now").font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
        }
        .padding(Space.s3).frame(maxWidth: Space.s8 * 12, alignment: .leading)
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
        .accessibilityElement(children: .combine).accessibilityLabel("Preview: claude is waiting on you")
    }
}
