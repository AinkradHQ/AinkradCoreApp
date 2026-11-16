import CoreUI
import SwiftUI

/// A room's Overview: what the room is about and the rules its items agree on, written by a model. Summary and the
/// instructions for AI sessions on the left, rule groups on the right; one column when the pane is narrow. Each state of
/// the writing (not written, writing, failed, no account, cloud off) says one thing and offers the one next step.
struct RoomOverviewTab: View {
    let model: BrainModel
    let room: RoomSummary
    private var o: RoomOverviewModel { model.roomOverview }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            if let n = o.notice {
                CoreNotice(symbol: "exclamationmark.triangle", title: n, tone: .warn)
            }
            content
        }
        .task(id: room.id) { await o.load(room.id) }
        .task(id: o.current?.state) { if o.current?.state == .writing { await o.watch(room.id) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room-overview")
    }

    @ViewBuilder private var content: some View {
        if let cur = o.current {
            switch cur.state {
            case .notWritten: notWritten
            case .needsAccount:
                BrainStateCard(
                    symbol: "person.crop.circle.badge.plus", title: "No AI account",
                    text: "Add an AI account in Settings to write this overview.",
                    primary: CoreAction("Open Settings") { openAccounts() })
            case .cloudOff:
                BrainStateCard(
                    symbol: "icloud.slash", title: "Cloud writing is off",
                    text: "Cloud writing is off for this room.",
                    primary: CoreAction("Open Room Settings") { model.candidates.paneMode = .settings })
            case .writing:
                StatusLine(cur: cur, busy: true) {}
                Columns {
                    Placeholder(widths: Self.leftLines)
                } right: {
                    Placeholder(widths: Self.rightLines)
                }
            case .failed:
                CoreNotice(
                    symbol: "exclamationmark.triangle", title: "Writing the overview failed.", text: cur.detail,
                    tone: .fail
                ) {
                    Button("Retry") { Task { await o.write(room.id) } }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(o.busy)
                }
                if let body = cur.overview { written(cur, body) }
            case .written:
                if let body = cur.overview { written(cur, body) } else { notWritten }
            }
        } else if case .failed(let why) = o.phase {
            BrainStateCard(
                symbol: "exclamationmark.triangle", title: "Unable to load the overview", text: why,
                primary: CoreAction("Try Again") { Task { await o.load(room.id) } })
        } else {
            BrainSkeleton(shape: .list)
        }
    }

    @ViewBuilder private func written(_ cur: RoomOverview, _ body: OverviewBody) -> some View {
        if cur.state == .written {
            StatusLine(cur: cur, busy: o.busy) { Task { await o.write(room.id) } }
        }
        Columns {
            OverviewSummary(overview: body)
            InstructionsCard(
                o: o, room: room.id, overview: body, approved: cur.instructionsApproved, text: cur.instructionsText)
        } right: {
            OverviewRulesColumn(o: o, room: room.id, rules: body.rules)
        }
    }

    private var notWritten: some View {
        let n = room.counts?.records
        let what = n.map { "the \($0.formatted()) in this room" } ?? "this room"
        return BrainStateCard(
            symbol: "sparkles", title: "No overview yet",
            text: "Core picks the items that matter among \(what), and your AI account writes a summary and rules.",
            primary: CoreAction("Write Overview") { Task { await o.write(room.id) } })
    }

    private func openAccounts() {
        model.host.shell.settings.selected = "accounts-link"
        model.host.shell.open(.settings)
    }

    // Line lengths of the placeholder, as fractions of the column (the mockup's skeleton).
    static let leftLines: [Double] = [0.9, 1, 0.7, 1, 0.6, 0, 1, 0.8, 1, 0.5]
    static let rightLines: [Double] = [0.9, 1, 0.7, 1, 0.6, 0, 1, 0.8, 1, 0.5]
}

/// "Written by the local model · updated 2 hours ago · Rewrite", or while writing the bar and how far it is.
private struct StatusLine: View {
    let cur: RoomOverview
    let busy: Bool
    let rewrite: () -> Void

    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "sparkles").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            if cur.state == .writing {
                Text("Writing…")
                // Several rooms at once get a bar that fills; one room waits behind the sweeping bar.
                if let p = cur.progress, p.total > 1 {
                    CoreMeter(Double(p.done) / Double(p.total), height: Space.s1 + 2, label: "Writing")
                        .frame(width: Space.s8 * 5)
                    Text("\(p.done) of \(p.total) rooms").monospacedDigit()
                } else {
                    CoreWorkingBar(width: Space.s8 * 5)
                    if !cur.detail.isEmpty { Text(cur.detail) }
                }
            } else {
                Text(line)
                Button(action: rewrite) {
                    Text("Rewrite").padding(.horizontal, Space.s1).frame(minHeight: MacSize.chip)
                }
                .buttonStyle(CoreQuietPressStyle(radius: Radius.chip, scale: 1, hoverFill: true)).disabled(busy)
                .help("Write this overview again from the room's items")
            }
        }
        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        .frame(minHeight: MacSize.controlSm, alignment: .leading)
    }

    private var line: String {
        var s = "Written by \(cur.writer)"
        if let d = SyncWords.date(cur.writtenAt) {
            let ago = SyncWords.ago(d)
            s += " · updated " + (ago.first?.isNumber == true ? ago : ago.prefix(1).lowercased() + ago.dropFirst())
        }
        return s + " ·"
    }
}
