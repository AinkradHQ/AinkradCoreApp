import CoreUI
import SwiftUI

/// The sessions list pane: what waits on you, the filter, one row per session, older ones as you scroll.
struct AgentsListView: View {
    @Bindable var model: AgentsModel
    @Environment(\.corePalette) private var palette
    @FocusState private var focusedRow: String?

    var body: some View {
        let waitingIDs = Set(model.pending.map(\.session))
        VStack(alignment: .leading, spacing: 0) {
            bar(waiting: waitingIDs.count)
            if model.shouldAskAboutNotifications {
                NotificationAsk(model: model).padding([.horizontal, .bottom], Space.s3)
            }
            if model.link == .reconnecting {
                NoticeBanner(
                    notice: InlineNotice(
                        title: "Reconnecting", detail: "Resuming from where you were. Nothing is lost.",
                        symbol: "arrow.triangle.2.circlepath")
                ).padding([.horizontal, .bottom], Space.s3)
            }
            if case .ended(let why) = model.link {
                NoticeBanner(notice: InlineNotice(title: "Live updates stopped", detail: why, tone: .fail))
                    .padding([.horizontal, .bottom], Space.s3)
            }
            CoreSegmented(
                "Filter sessions",
                segments: [
                    CoreSegment(AgentFilter.all, "All \(model.count(.all))"),
                    CoreSegment(.needsYou, "Needs you \(waitingIDs.count)"),
                    CoreSegment(.active, "Active \(model.count(.active))"),
                    CoreSegment(.ended, "Ended \(model.count(.ended))"),
                ], selection: $model.filter
            )
            .padding(.horizontal, Space.s3).padding(.bottom, Space.s2)
            content(waitingIDs)
        }
        .accessibilityElement(children: .contain)
    }

    private func bar(waiting: Int) -> some View {
        let active = model.count(.active)
        let summary =
            Text(waiting > 0 ? "\(waiting) waiting on you" : "Nothing waiting on you")
            .fontWeight(waiting > 0 ? .semibold : .regular)
            .foregroundStyle(waiting > 0 ? palette.navActiveInk : palette.text)
            + Text(" · \(active) active").foregroundStyle(palette.text2)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s2) {
                summary.lineLimit(1)
                Spacer(minLength: Space.s2)
                buttons(waiting)
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                summary
                HStack(spacing: Space.s2) { buttons(waiting) }
            }
        }
        .font(.system(size: MacTextSize.body))
        .padding(.horizontal, Space.s3).padding(.bottom, Space.s3)
    }

    @ViewBuilder
    private func buttons(_ waiting: Int) -> some View {
        Button {
            model.openInbox()
        } label: {
            Text(waiting > 0 ? "Approvals \(waiting)" : "Approvals")
        }
        .buttonStyle(CoreButtonStyle(.secondary, size: .small)).help("See what agents wait on you for")
        .accessibilityLabel(waiting > 0 ? "Approvals, \(waiting) waiting" : "Approvals")
        Button {
            model.openNewSession()
        } label: {
            Text("New session")
        }
        .buttonStyle(CoreButtonStyle(.prominent, size: .small)).help("Start an agent on a runner")
    }

    @ViewBuilder
    private func content(_ waitingIDs: Set<String>) -> some View {
        switch model.sessions.load {
        case .idle, .loading:
            ScrollView { SkeletonRows().padding(.horizontal, Space.s3) }
        case .failed(let why):
            Message(
                title: "Could not load sessions", text: why, action: "Try again", prominent: false
            ) { model.retryList() }
        case .ready:
            let rows = model.shown()
            if model.sessions.items.isEmpty {
                Message(
                    title: "No agent sessions yet",
                    text: "Start one and it runs on a runner of the Home Core. You can close this Mac; it keeps going.",
                    action: "New session", prominent: true
                ) { model.openNewSession() }
            } else if rows.isEmpty {
                Message(title: "Nothing here", text: "No sessions match this filter.", action: nil, prominent: false) {}
            } else {
                list(rows, waitingIDs)
            }
        }
    }

    private func list(_ rows: [AgentSessionInfo], _ waitingIDs: Set<String>) -> some View {
        ScrollView {
            LazyVStack(spacing: Space.s1) {
                ForEach(rows) { s in
                    Button {
                        model.openSession(s.id)
                    } label: {
                        SessionRow(session: s, runner: model.runnerName(s.runner), waiting: waitingIDs.contains(s.id))
                    }
                    .buttonStyle(AgentRowStyle(selected: model.selected == s.id))
                    .focused($focusedRow, equals: s.id)
                    .accessibilityLabel(label(s, waiting: waitingIDs.contains(s.id)))
                    .accessibilityHint("Opens the session")
                    .onAppear { if s.id == rows.last?.id && model.filter == .all { model.loadMore() } }
                }
                Text(
                    model.sessions.hasMore
                        ? "Showing \(model.sessions.items.count) sessions. Older ones load as you scroll."
                        : "Showing all \(model.sessions.items.count) sessions."
                )
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Space.s2).padding(.bottom, Space.s2)
        }
        .onKeyPress(.downArrow) { move(rows, 1) }
        .onKeyPress(.upArrow) { move(rows, -1) }
    }

    private func move(_ rows: [AgentSessionInfo], _ step: Int) -> KeyPress.Result {
        guard let cur = focusedRow, let i = rows.firstIndex(where: { $0.id == cur }) else {
            focusedRow = rows.first?.id
            return .handled
        }
        focusedRow = rows[min(max(i + step, 0), rows.count - 1)].id
        return .handled
    }

    private func label(_ s: AgentSessionInfo, waiting: Bool) -> String {
        let st = AgentWords.status(s, waiting: waiting).label
        return "\(s.harness) on \(model.runnerName(s.runner)), \(st)"
    }
}

private struct Message: View {
    let title: String
    let text: String
    let action: String?
    let prominent: Bool
    let run: () -> Void
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(spacing: Space.s2) {
            Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
            Text(text).foregroundStyle(palette.text2).multilineTextAlignment(.center)
            if let action {
                Button(action, action: run).buttonStyle(CoreButtonStyle(prominent ? .prominent : .secondary))
                    .padding(.top, Space.s2)
            }
        }
        .frame(maxWidth: Space.s8 * 10).padding(Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// The one question about macOS notifications, in the app's own words, before macOS is asked.
struct NotificationAsk: View {
    @Bindable var model: AgentsModel
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Label("Get told when an agent needs you", systemImage: "bell").font(
                .system(size: MacTextSize.headline, weight: .semibold))
            Text("Ainkrad can show a macOS banner for each new approval. macOS will ask you to allow it once.")
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s2) {
                Spacer(minLength: 0)
                Button("Not now") { model.declineNotificationsForNow() }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                Button("Turn on") { Task { await model.turnOnNotifications() } }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .small))
            }
        }
        .padding(Space.s3)
        .background(palette.glassCard, in: coreShape(Radius.row))
        .overlay { coreShape(Radius.row).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }
}

struct SessionRow: View {
    let session: AgentSessionInfo
    let runner: String
    let waiting: Bool
    @Environment(\.corePalette) private var palette

    var body: some View {
        let st = AgentWords.status(session, waiting: waiting)
        HStack(alignment: .top, spacing: Space.s3) {
            AgentMark(harness: session.harness)
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text(session.harness).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: Space.s2)
                    StateBadge(st.label, tone: st.tone, symbol: st.symbol)
                }
                Text("\(runner) · \(session.shortID)").font(.system(size: MacTextSize.body)).foregroundStyle(
                    palette.text2
                )
                .lineLimit(1).truncationMode(.middle)
                HStack(spacing: Space.s2) {
                    if let u = session.usage {
                        Text("\(AgentWords.tokens(u.tokens)) tokens")
                        if let c = AgentWords.cost(u.costMicros) { Text(c) }
                    }
                    Spacer(minLength: 0)
                    if session.live {
                        Text(session.createdAt, style: .timer)
                    } else {
                        Text(AgentWords.ago(session.endedAt ?? session.updatedAt))
                    }
                }
                .font(.system(size: MacTextSize.meta, design: .monospaced)).foregroundStyle(palette.text2)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(coreShape(Radius.row))
        .accessibilityElement(children: .combine)
    }
}
