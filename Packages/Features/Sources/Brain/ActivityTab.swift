import CoreUI
import SwiftUI

/// Activity: who searched, saved or was refused, room by room, and the egress log of what a model ever received from one
/// room. Ids and decisions only, never memory text. It starts on the viewing room; "All mounted rooms" is a choice.
struct ActivityTab: View {
    let model: BrainModel

    var body: some View {
        @Bindable var a = model.activity
        VStack(alignment: .leading, spacing: Space.s4) {
            header(a)
            PausedBanner(model: model, full: false)
            switch a.phase {
            case .loading:
                BrainSkeleton(shape: .list)
            case .failed(let why, let code):
                BrainStateCard(
                    symbol: "exclamationmark.triangle", title: "Activity could not load", text: why,
                    primary: CoreAction("Try again") { a.retry() }
                )
                .help("Code: \(code)")
            case .ready:
                HStack(alignment: .top, spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        if a.view == .feed { FeedView(model: model) } else { EgressView(model: model) }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    detail(a).frame(width: Space.s8 * 9.5)
                }
            }
        }
        .task { a.enter() }
        .onChange(of: model.viewingID) { a.enter() }
        .onDisappear { a.leave() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-activity")
    }

    private func header(_ a: ActivityModel) -> some View {
        @Bindable var a = a
        return HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                BrainTitle("Activity")
                Text("Who touched which room, and what was refused. Never any memory text.")
                    .foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s3)
            if let q = model.overview?.flags.offlineQueued {
                BrainChip(
                    "Offline, \(q) queued", GlassInk.slate,
                    help: "The local Core answers; the remote server is unreachable.")
            }
            HStack(spacing: Space.s1) {
                coreShape(2).fill(GlassInk.blue).frame(width: 6, height: 6).accessibilityHidden(true)
                Text("Live").foregroundStyle(GlassInk.secondary)
            }
            .help("New rows arrive within seconds.")
            CoreSegmented(
                "View",
                segments: [CoreSegment(ActivityView.feed, "Activity"), CoreSegment(.egress, "Sent out of this Mac")],
                selection: $a.view
            )
            .help("Egress log: everything a model ever received from a room.")
        }
    }

    @ViewBuilder private func detail(_ a: ActivityModel) -> some View {
        if a.view == .feed, let e = a.selectedEvent {
            ActivityDetail(
                title: e.action, chip: chip(e.result), sub: "\(e.at) · \(e.actor)",
                rule: e.result == .blocked
                    ? e.rule.map { .init(name: $0.name, code: $0.code, text: e.reason, fix: $0.fix) } : nil,
                why: e.result == .blocked ? nil : e.reason,
                sentence: BrainWords.sentence(e, room: model.room(e.room)?.name), lines: e.details,
                note: BrainWords.activityIdsOnly)
        } else if a.view == .egress, let c = a.selectedCall {
            ActivityDetail(
                title: c.kind.label, chip: c.sent ? ("Sent", GlassInk.blue) : ("Blocked", GlassInk.red),
                sub: "\(c.at) · \(c.actor)",
                rule: c.block.map {
                    .init(name: $0.ruleName, code: $0.rawValue, text: $0.sentence, fix: "Nothing was sent.")
                },
                why: nil, sentence: BrainWords.sentence(c), lines: c.details,
                note: "Ids and codes only. No memory text was kept.")
        } else {
            BrainCard(
                "Details",
                sub: a.view == .feed
                    ? "Pick a row to see its ids and codes. This log never keeps memory text."
                    : "Pick a row to see its ids and codes. Records are listed by id, never by text."
            ) {}
        }
    }
}

func chip(_ r: ActivityResult) -> (String, Color) { (r.label, r == .ok ? GlassInk.green : GlassInk.red) }

private struct FeedView: View {
    let model: BrainModel

    var body: some View {
        @Bindable var a = model.activity
        VStack(alignment: .leading, spacing: Space.s3) {
            filters(a)
            if a.isOffline {
                BrainNotice(
                    symbol: "wifi.slash", title: "Showing what this Mac has",
                    text: "Activity from your other devices arrives when you are back online.")
            }
            if a.events.isEmpty {
                BrainStateCard(
                    symbol: "tray", title: "Nothing has happened yet",
                    text: "Activity appears here as agents and your devices use your rooms.")
            } else if a.visible.isEmpty {
                BrainStateCard(
                    symbol: "line.3.horizontal.decrease", title: "No activity matches",
                    text: "Nothing fits these filters.", primary: CoreAction("Clear filters") { a.clearFilters() })
            } else {
                LazyVStack(spacing: Space.s2) {
                    ForEach(a.visible) { e in
                        ActivityRowView(
                            time: e.at, title: e.action,
                            subtitle: "\(e.actor) on \(e.device) · \(model.room(e.room)?.name ?? "No room chosen")",
                            why: e.result == .ok ? nil : e.reason,
                            blockedBy: e.result == .blocked ? e.rule.map { BrainWords.blockedBy($0.name) } : nil,
                            help: e.id, chip: chip(e.result), selected: a.selectedID == e.id,
                            fresh: a.fresh.contains(e.id)
                        ) { a.selectedID = e.id }
                        .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: Motion.ui), value: a.visible.map(\.id))
                if a.hasMore {
                    Button("Load more") { a.loadMore() }.buttonStyle(CoreButtonStyle(.secondary))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onChange(of: a.announcement) { _, text in if let text, !text.isEmpty { CoreAnnounce.post(text) } }
    }

    private func filters(_ a: ActivityModel) -> some View {
        @Bindable var a = a
        let kinds = ActivityKind.allCases.map { CoreSegment($0, $0.title) }
        let who = [CoreSelectOption("", "Anyone")] + a.people.map { CoreSelectOption($0, $0) }
        let results =
            [CoreSelectOption(ActivityResult?.none, "Any result")]
            + ActivityResult.allCases.map { CoreSelectOption(Optional($0), $0.label) }
        return VStack(alignment: .leading, spacing: Space.s2) {
            CoreSegmented("Kind", segments: kinds, selection: $a.filter.kind)
            HStack(alignment: .bottom, spacing: Space.s2) {
                CoreSelect("Who", selection: $a.filter.who, options: who)
                CoreSelect("Result", selection: $a.filter.result, options: results)
                if a.filter.isActive {
                    Button("Clear filters") { a.clearFilters() }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
        }
    }
}

private struct EgressView: View {
    let model: BrainModel

    var body: some View {
        @Bindable var a = model.activity
        let room = a.egressRoomSummary
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .bottom, spacing: Space.s3) {
                CoreSelect(
                    "Room",
                    selection: Binding(get: { a.egressRoomID ?? "" }, set: { a.egressRoom = $0 }),
                    options: model.mountedRooms.map { CoreSelectOption($0.id, $0.name) }
                )
                .frame(width: Space.s8 * 6)
                Text(
                    "Everything a model ever received from this room, one row per try. Used for a provider revocation report."
                )
                .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let why = a.egressFailed {
                BrainStateCard(
                    symbol: "exclamationmark.triangle", title: "This list could not load", text: why,
                    primary: CoreAction("Try again") { Task { await a.loadEgress() } })
            } else if a.egress.isEmpty, let room {
                if room.mode == .localOnly {
                    BrainStateCard(
                        symbol: "lock", title: BrainWords.leftNothing(room.name), text: BrainWords.leftNothingText)
                } else {
                    BrainStateCard(
                        symbol: "tray", title: "No model calls yet",
                        text: "Calls from \(room.name) to a model appear here, allowed or blocked.")
                }
            } else {
                let sent = a.egress.filter { $0.sent && !$0.stayedHere }.count
                let blocked = a.egress.filter { !$0.sent }.count
                HStack(spacing: Space.s4) {
                    count(a.egress.count, "tries")
                    count(sent, "sent to a cloud model")
                    count(blocked, "blocked")
                }
                LazyVStack(spacing: Space.s2) {
                    ForEach(a.egress) { c in
                        ActivityRowView(
                            time: c.at, title: c.kind.label, subtitle: subtitle(c), why: c.block?.sentence,
                            blockedBy: c.block.map { BrainWords.blockedBy($0.ruleName) }, help: c.id,
                            chip: c.block != nil
                                ? ("Blocked", GlassInk.red)
                                : c.stayedHere ? ("Stayed here", GlassInk.slate) : ("Sent", GlassInk.blue),
                            selected: a.selectedID == c.id, fresh: false
                        ) { a.selectedID = c.id }
                    }
                }
            }
        }
    }

    private func count(_ n: Int, _ text: String) -> some View {
        HStack(spacing: Space.s1) {
            Text("\(n)").font(.system(size: MacTextSize.title, weight: .semibold)).monospacedDigit()
            Text(text).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
        }
    }

    private func subtitle(_ c: EgressCall) -> String {
        let place =
            c.provider == .local
            ? "stayed on this Mac" : c.provider == .approvedCloud ? "approved cloud" : "not approved"
        guard c.sent else { return "\(c.target) · \(place)" }
        return
            "\(c.target) · \(place) · \(String(format: "%.1f", Double(c.bytes) / 1000)) KB out · \(c.redacted) redacted"
    }
}
