import CoreUI
import SwiftUI

/// The top of a place's Overview: what Brain wrote about the place, "updated … · it rewrites this as it learns" and a quiet
/// Rewrite Now; while it is written, soft lines and a live bar. Each state that blocks the writing says why in one line
/// with the one next step, in the same card.
struct PlaceSummary: View {
    let model: BrainModel
    let room: RoomSummary
    let place: PlaceWire?
    private var o: RoomOverviewModel { model.roomOverview }
    private var cur: RoomOverview? { o.roomID == room.id ? o.current : nil }

    private var autoWrites: Bool { model.writesOverviews }
    private var things: Int { room.counts?.records ?? place?.total ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) { content }
            .padding(.horizontal, Space.s5).padding(.vertical, Space.s4 + 2)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .coreWell()
            .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: cur?.isWriting)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("place-summary")
    }

    @Environment(\.accessibilityReduceMotion) private var reduce

    @ViewBuilder private var content: some View {
        if let cur {
            switch cur.state {
            case _ where cur.isWriting:
                if let body = cur.overview {
                    written(cur, body, rewriting: true)
                } else {
                    writing(cur)
                }
            case .written:
                if let body = cur.overview { written(cur, body) } else { writing(cur) }
            case .failed:
                if let body = cur.overview {
                    written(cur, body)
                } else {
                    head("What \(room.name) is", "Brain could not write it this time")
                }
                note("The last try did not finish: \(cur.detail)", action: "Try Again") { rewrite() }
            case .needsAccount:
                head("What \(room.name) is", "Brain writes this with your AI account")
                note("Add an AI account and Brain writes it by itself.", action: "Open Accounts") { openAccounts() }
            case .cloudOff:
                head("What \(room.name) is", "Written with your AI account")
                note(
                    "This place learns only on your own machines, so no overview is written for it.",
                    action: "Open Settings"
                ) { model.candidates.paneMode = .settings }
            case .notWritten, .writing:
                if things == 0 {
                    head("What \(room.name) is", "Written by Brain once it has read something here")
                } else if autoWrites {
                    writing(cur)
                } else {
                    // An older Core does not write overviews by itself.
                    head("What \(room.name) is", "Not written yet") { quiet("Write Now", "sparkles", rewrite) }
                }
            }
        } else if case .failed(let why) = o.phase, o.roomID == room.id {
            head("What \(room.name) is", "Unable to load it")
            note(why, action: "Try Again") { Task { await o.load(room.id) } }
        } else {
            head("What \(room.name) is", "Reading…")
            lines(live: false)
        }
    }

    private func written(_ cur: RoomOverview, _ body: OverviewBody, rewriting: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            head("What \(room.name) is", rewriting ? "Brain is rewriting this now" : updated(cur)) {
                if !rewriting { quiet("Rewrite Now", "arrow.clockwise", rewrite) }
            }
            .help("Written with \(cur.writer)")
            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach(Array(body.paragraphs.enumerated()), id: \.offset) { _, p in
                    Text(p).font(.system(size: 14.5)).lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .frame(maxWidth: 880, alignment: .leading)
                }
            }
            if !body.facts.rows.isEmpty {
                HStack(spacing: Space.s2) {
                    ForEach(body.facts.rows, id: \.label) { r in
                        HStack(spacing: Space.s1) {
                            Text(r.label).foregroundStyle(GlassInk.secondary)
                            Text(r.value).lineLimit(1)
                        }
                        .coreFont(size: MacTextSize.meta)
                        .padding(.horizontal, Space.s2).padding(.vertical, 3)
                        .background(GlassInk.well, in: coreShape(Radius.chip))
                        .help("\(r.label): \(r.value)")
                    }
                }
            }
            if rewriting { LiveBar(progress: cur.progress) }
        }
    }

    /// "Writing the overview": what it does now, soft lines where the text will be and a live bar.
    private func writing(_ cur: RoomOverview) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            head("Writing the overview", writingLine(cur))
            lines(live: true)
            LiveBar(progress: cur.progress)
        }
        .accessibilityIdentifier("place-summary-writing")
    }

    private func writingLine(_ cur: RoomOverview) -> String {
        if let wait = OverviewSteps(cur.stage, picked: cur.picked)?.wait { return wait }
        if let n = cur.picked { return "Reading the \(n.formatted()) things that matter most here" }
        if things > 0 { return "Reading the \(things.formatted()) things it read here" }
        return "Reading what it knows here"
    }

    private func lines(live: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s2 + 1) {
            ForEach(Array([0.92, 1, 0.86, 0.97, 0.64].enumerated()), id: \.offset) { _, w in
                Color.clear.frame(height: Space.s3).frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in CoreSkeleton(coreShape(4)).frame(width: g.size.width * w) }
                    }
            }
        }
        .opacity(live ? 1 : 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Writing")
    }

    private func head<R: View>(_ title: String, _ meta: String, @ViewBuilder right: () -> R = { EmptyView() })
        -> some View
    {
        HStack(alignment: .center, spacing: Space.s3) {
            BrainTile(symbol: "sparkles", lit: true, size: Space.s6 + Space.s1 + 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold).accessibilityAddTraits(.isHeader)
                Text(meta).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s3)
            right()
        }
    }

    private func note(_ text: String, action: String, _ run: @escaping () -> Void) -> some View {
        HStack(spacing: Space.s3) {
            Text(text).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s3)
            quiet(action, nil, run)
        }
    }

    private func quiet(_ title: String, _ symbol: String?, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
        }
        .buttonStyle(CoreButtonStyle(.plain, size: .small)).disabled(o.busy)
        .help(title == "Rewrite Now" ? "Write the overview again now" : title)
    }

    private func updated(_ cur: RoomOverview) -> String {
        let at = SyncWords.date(cur.cardAt ?? cur.writtenAt).map { "updated \(SyncWords.agoInLine($0)) · " } ?? ""
        return "Written by Brain · \(at)it rewrites this as it learns"
    }

    private func rewrite() { Task { await o.write(room.id) } }

    private func openAccounts() {
        model.host.shell.settings.selected = "accounts-link"
        model.host.shell.open(.settings)
    }
}

/// The writing's live bar: it fills when the Core says how far it is (several places at once), else it sweeps.
private struct LiveBar: View {
    let progress: OverviewProgress?

    var body: some View {
        if let p = progress, p.total > 1 {
            CoreMeter(Double(p.done) / Double(p.total), height: Space.s1, label: "Writing")
        } else {
            GeometryReader { g in CoreWorkingBar(width: g.size.width) }.frame(height: Space.s1)
        }
    }
}
