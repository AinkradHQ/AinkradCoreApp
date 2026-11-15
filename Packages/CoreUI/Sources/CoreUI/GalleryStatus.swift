#if DEBUG
import SwiftUI

extension CoreUIGallery {
    // MARK: Status

    @ViewBuilder var status: some View {
        GSpec("StateBadge", "A state from the Core: a square in its colour and the word. Never colour alone.") {
            VStack(alignment: .leading, spacing: Space.s2) {
                badgeLine("Session", SessionState.table.map { StateBadge($0.state) })
                badgeLine("Outcome", SessionOutcome.table.map { StateBadge($0.state) })
                badgeLine("Terminal", TerminalState.table.map { StateBadge($0.state) })
                badgeLine("Account", AccountState.table.map { StateBadge($0.state) })
                badgeLine("Issue", IssueState.table.map { StateBadge($0.state) })
                badgeLine("Run", RunState.table.map { StateBadge($0.state) })
                badgeLine("Unknown", [StateBadge(RunState(rawValue: "paused_by_server"))])
            }
        }
        GSpec("CountBadge", "A count beside a title: accent, needs you (amber) or quiet.") {
            HStack(spacing: Space.s4) {
                GVariant("accent") { CountBadge(3) }
                GVariant("needsYou") { CountBadge(2, tone: .needsYou) }
                GVariant("quiet") { CountBadge(12, tone: .quiet) }
                GVariant("large") { CountBadge(120) }
                GVariant("zero shown") { CountBadge(0, tone: .quiet, showsZero: true) }
            }
        }
        GSpec("CoreChip", "A neutral label: a fact, never a state.") {
            HStack(spacing: Space.s3) {
                CoreChip("Cloud")
                CoreChip("Needs a look", symbol: "exclamationmark.triangle")
                CoreChip("2\u{00A0}ms")
            }
        }
        GSpec("AppStatChip", "A footer count with its glyph.") {
            HStack(spacing: Space.s3) {
                AppStatChip("checkmark", "12 done", GlassInk.green)
                AppStatChip("hand.raised", "3 waiting", GlassInk.amber)
                AppStatChip("xmark", "1 failed", GlassInk.red)
                AppStatChip("clock", "4 queued", GlassInk.slate)
            }
        }
        GSpec("IconTile", "A glyph in its hue on a flat well: a subject's mark beside its title.") {
            HStack(alignment: .bottom, spacing: Space.s4) {
                ForEach(
                    [
                        ("accent", GlassInk.blue), ("green", GlassInk.green), ("amber", GlassInk.amber),
                        ("red", GlassInk.red), ("slate", GlassInk.slate),
                    ], id: \.0
                ) { name, hue in
                    GVariant(name) { IconTile("server.rack", hue: hue) }
                }
                GVariant("24") { IconTile("terminal", hue: GlassInk.blue, size: 24) }
                GVariant("48") { IconTile("terminal", hue: GlassInk.blue, size: 48) }
            }
        }
    }

    func badgeLine(_ name: String, _ items: [StateBadge]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(name).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .frame(width: Space.s8 * 2, alignment: .leading)
            HStack(spacing: Space.s3) { ForEach(items.indices, id: \.self) { items[$0] } }
        }
    }

    // MARK: Feedback

    @ViewBuilder var feedback: some View {
        GSpec("CoreNotice", "A message inside content, in its tone, with an optional action.") {
            VStack(spacing: Space.s2) {
                CoreNotice(symbol: "info.circle", title: "Quiet", text: "Something worth knowing.", tone: .queue)
                CoreNotice(symbol: "checkmark.circle", title: "Running", text: "Two sessions are working.", tone: .run)
                CoreNotice(symbol: "info.circle", title: "Done", text: "The import finished.", tone: .done)
                CoreNotice(symbol: "hand.raised", title: "Needs you", text: "An approval waits.", tone: .warn) {
                    Button("Review") {}.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
                CoreNotice(
                    symbol: "exclamationmark.triangle", title: "Failed", text: "The runner stopped.", tone: .fail
                ) {
                    Button("Retry") {}.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
        }
        GSpec("ConnectionBanner", "The link to the Core, across the top of a pane.") {
            VStack(spacing: Space.s2) {
                ConnectionBanner(.offline, retry: {})
                ConnectionBanner(.reconnecting)
                ConnectionBanner(.loading)
                ConnectionBanner(.error("The request timed out. Check the server and try again."), retry: {})
            }
        }
        GSpec("LinkBanner", "What the link is doing right now.") {
            VStack(spacing: Space.s2) {
                LinkBanner(.resuming(since: nil), retry: {})
                LinkBanner(.rateLimited(until: nil))
                LinkBanner(.renewing)
                LinkBanner(.restarted, dismiss: {})
            }
        }
        GSpec("CoreToast", "A short message at the bottom, often with Undo.") {
            VStack(alignment: .leading, spacing: Space.s2) {
                CoreToast("Session closed", undo: {})
                CoreToast("Settings saved", kind: .info)
                CoreToast("Backup is two days old", kind: .warn)
                CoreToast("Could not reach the runner", kind: .error, actionTitle: "Retry", undo: {})
                Button("Show a live toast") { toast = ToastItem("Terminal moved", undo: {}) }
                    .buttonStyle(CoreButtonStyle(.secondary))
            }
        }
        GSpec("CoreWorkingBar, CoreBusyBar", "Something is happening; no promise of how long.") {
            HStack(spacing: Space.s5) {
                GVariant("CoreWorkingBar") { CoreWorkingBar() }
                GVariant("CoreBusyBar") { CoreBusyBar().frame(width: Space.s8 * 7) }
            }
        }
        GSpec("CoreSkeleton", "The shape of content that is still loading.") {
            HStack(spacing: Space.s3) {
                CoreSkeleton().frame(width: 160, height: 28)
                CoreSkeleton(coreShape(Radius.cardMac)).frame(width: 120, height: 48)
            }
        }
        GSpec("CoreStateCard", "An empty, done or failed state: what happened and the one next step.") {
            CoreStateCard(
                symbol: "tray", title: "Nothing here yet", line: "Sessions you start show up here.",
                secondary: CoreAction("Learn more") {}, primary: CoreAction("New session") {})
        }
    }

    // MARK: Data

    @ViewBuilder var data: some View {
        GSpec("CoreMeter", "Progress toward a real limit. Never decoration.") {
            VStack(alignment: .leading, spacing: Space.s3) {
                GVariant("30%") { CoreMeter(0.3, label: "Used").frame(width: Space.s8 * 8) }
                GVariant("77%") { CoreMeter(0.77, label: "Used").frame(width: Space.s8 * 8) }
                GVariant("Low: near the limit") { CoreMeter(0.95, low: true, label: "Used").frame(width: Space.s8 * 8) }
                GVariant("Tall") { CoreMeter(0.5, height: Space.s2, label: "Used").frame(width: Space.s8 * 8) }
            }
        }
        GSpec("CoreSpark", "A small trend in a row.") {
            HStack(spacing: Space.s5) {
                GVariant("run") { CoreSpark([3, 5, 2, 7, 4, 6, 8], tone: .run).frame(width: 120, height: 28) }
                GVariant("warn") { CoreSpark([3, 5, 2, 7, 9, 10, 12], tone: .warn).frame(width: 120, height: 28) }
                GVariant("fail") { CoreSpark([8, 6, 9, 3, 2, 1, 0], tone: .fail).frame(width: 120, height: 28) }
            }
        }
        GSpec("CoreHeat", "Activity over days.") {
            CoreHeat((0..<28).map { Double(($0 * 7) % 10) / 10 }).frame(width: Space.s8 * 8, height: 40)
        }
        GSpec("CoreSlots", "Places used out of a capacity.") {
            HStack(spacing: Space.s5) {
                GVariant("2 of 4") { CoreSlots(used: 2, capacity: 4) }
                GVariant("4 of 4") { CoreSlots(used: 4, capacity: 4) }
                GVariant("0 of 2") { CoreSlots(used: 0, capacity: 2) }
            }
        }
    }
}
#endif
