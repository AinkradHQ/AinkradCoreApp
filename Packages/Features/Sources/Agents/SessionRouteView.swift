import CoreUI
import SwiftUI

extension AgentsModel {
    /// Reads the account's name and, for a run that moved, its attempts, now and every 15 s while the session is live.
    func followRoute(_ id: String) async {
        while !Task.isCancelled {
            if let api, let r = sessions.session(id)?.route {
                if let a = r.account, accountNames[a] == nil, let n = try? await api.accountName(a) {
                    accountNames[a] = n
                }
                if let run = r.run, r.moved || r.attempt ?? 0 > 0, let list = try? await api.attempts(run: run),
                    !list.isEmpty
                {
                    attempts[run] = list.sorted { ($0.route?.attempt ?? 0) < ($1.route?.attempt ?? 0) }
                }
            }
            guard sessions.session(id)?.live == true else { return }
            try? await Task.sleep(for: .seconds(15))
        }
    }

    func chainName(_ r: SessionRoute) -> String? { chains.first { $0.id == r.chainID }?.name }
}

/// Under the session's head: where the scheduler put it, in plain sentences. Waiting, moved and "no account left" are notices;
/// the attempts of a run that moved are a list. Nothing shows for a device that was given no route.
struct SessionRouteCues: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo

    var body: some View {
        if let r = session.route {
            VStack(spacing: Space.s2) {
                if let w = r.waiting, session.live {
                    let t = SessionCues.waiting(w, now: Date())
                    CoreNotice(symbol: "hourglass", title: t.title, text: t.text, tone: .warn)
                }
                if let m = SessionCues.moved(r) {
                    CoreNotice(symbol: "arrow.triangle.branch", title: m.title, text: m.text, tone: .queue)
                }
                if let e = r.ended, let t = SessionCues.notMoved(e) {
                    CoreNotice(symbol: "xmark.octagon", title: t.title, text: t.text, tone: .fail)
                }
                if session.live, let u = SessionCues.upstream(r.upstreamClass) {
                    CoreNotice(symbol: "exclamationmark.triangle", title: u, tone: .warn)
                        .help("The provider's last answer to this session: \(r.upstreamClass ?? "")")
                }
                if let run = r.run, let list = model.attempts[run], list.count > 1 {
                    AttemptList(model: model, attempts: list, current: session.id)
                }
            }
        }
    }
}

/// Every attempt of one run: which account it held and how it ended. Open one to see its transcript.
private struct AttemptList: View {
    @Bindable var model: AgentsModel
    let attempts: [AgentSessionInfo]
    let current: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("Attempts of this run").font(.system(size: MacTextSize.meta, weight: .semibold))
                .foregroundStyle(GlassInk.secondary)
            ForEach(attempts) { a in
                Button {
                    model.openSession(a.id)
                } label: {
                    HStack(spacing: Space.s2) {
                        Image(systemName: a.id == current ? "circle.inset.filled" : "square.stack")
                            .foregroundStyle(a.id == current ? GlassInk.blueInk : GlassInk.secondary)
                        Text(SessionCues.attempt(a))
                        if let acc = a.route?.account, let n = model.accountNames[acc] {
                            Text("on \(n)").foregroundStyle(GlassInk.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: MacTextSize.body)).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open this attempt")
            }
        }
        .padding(Space.s3)
        .background(GlassInk.well.opacity(0.7), in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
    }
}
