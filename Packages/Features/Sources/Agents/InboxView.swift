import CoreUI
import SwiftUI

/// Approvals: everything agents wait on you for, newest request last, with what was decided since this Mac opened.
struct InboxView: View {
    @Bindable var model: AgentsModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let pending = model.pending
        let decided = model.decided
        AgentDialogCard(title: "Approvals", width: Space.s8 * 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text(
                        pending.isEmpty
                            ? "Nothing is waiting on you."
                            : "\(pending.count) \(pending.count == 1 ? "agent is" : "agents are") waiting on you."
                    )
                    .foregroundStyle(palette.text2)
                    Label(
                        "Approving an agent action needs Touch ID. After one, the others need none for a while.",
                        systemImage: "lock.shield"
                    )
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
                Button("Done") { model.shell.closeDialog() }.buttonStyle(.coreSecondary).keyboardShortcut(.cancelAction)
            }
        }
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
