#if DEBUG
import SwiftUI

/// Debug gallery: every component in every state. Pinned states (hover, pressed, focus) use `coreForcedInteraction`.
public struct CoreUIGallery: View {
    @Environment(\.colorScheme) private var scheme
    @State private var segment = "all"
    @State private var rowSelected = "b"
    @State private var toast: ToastItem?
    @State private var confirm = false
    @State private var destructive = false

    public init() {}

    private var palette: Palette { scheme == .dark ? .night : .day }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s6) {
                Text("CoreUI Gallery").font(.system(size: MacTextSize.large, weight: .semibold))
                buttons
                surfaces
                rows
                badges
                segmented
                banners
                overlays
            }
            .padding(Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LinearGradient(colors: [palette.surface, palette.bg], startPoint: .top, endPoint: .bottom))
        .coreTheme()
        .coreToast($toast)
        .coreConfirm(
            "Close this session?", isPresented: $confirm, message: "The agent stops and its work is kept.",
            confirmTitle: "Close"
        ) {
            toast = ToastItem("Session closed", undo: {})
        }
        .coreConfirm(
            "Delete this terminal?", isPresented: $destructive, message: "This cannot be undone from here.",
            confirmTitle: "Delete",
            destructive: true
        ) { toast = ToastItem("Terminal deleted", undo: {}) }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title).font(.system(size: MacTextSize.title, weight: .semibold)).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var buttons: some View {
        section("Buttons") {
            let states: [(String, CoreInteraction?)] = [
                ("Rest", nil), ("Hover", .hover), ("Pressed", .pressed), ("Focus", .focused),
            ]
            ForEach([CoreButtonKind.prominent, .secondary, .plain], id: \.self) { kind in
                HStack(spacing: Space.s3) {
                    ForEach(states, id: \.0) { state in
                        Button(state.0) {}.buttonStyle(CoreButtonStyle(kind)).environment(
                            \.coreForcedInteraction, state.1)
                    }
                    Button("Disabled") {}.buttonStyle(CoreButtonStyle(kind)).disabled(true)
                    Button("Busy") {}.buttonStyle(CoreButtonStyle(kind, busy: true))
                }
            }
            HStack(spacing: Space.s3) {
                Button("Small") {}.buttonStyle(CoreButtonStyle(.prominent, size: .small))
                Button("Medium") {}.buttonStyle(CoreButtonStyle(.prominent, size: .medium))
                Button("Large") {}.buttonStyle(CoreButtonStyle(.prominent, size: .large))
            }
        }
    }

    private var surfaces: some View {
        section("Clear glass control and material panel") {
            HStack(spacing: Space.s4) {
                Label("Glass control", systemImage: "sparkles").padding(Space.s3).coreGlass()
                Text("Regular material panel. Content lives here; glass never sits on it.").corePanel()
            }
        }
    }

    private var rows: some View {
        section("Rows") {
            VStack(spacing: Space.s2) {
                CoreRow(
                    "Rest", subtitle: "Leading icon, title, subtitle, trailing state", symbol: "terminal", action: {}
                ) {
                    StateBadge(SessionState.running)
                }
                CoreRow("Hover", subtitle: "Pointer over the row", symbol: "terminal", action: {}) {
                    StateBadge(RunState.queued)
                }
                .environment(\.coreForcedInteraction, .hover)
                CoreRow("Selected", subtitle: "The current row", symbol: "terminal", selected: true, action: {}) {
                    StateBadge(IssueState.inReview)
                }
                CoreRow("Focus", subtitle: "Keyboard focus ring", symbol: "terminal", action: {}) {
                    StateBadge(AccountState.cooling)
                }
                .environment(\.coreForcedInteraction, .focused)
                CoreRow("Disabled", subtitle: "Not available", symbol: "terminal", action: {}) {
                    StateBadge(TerminalState.exited)
                }
                .disabled(true)
            }
        }
    }

    private var badges: some View {
        section("State badges") {
            badgeLine("Session", SessionState.table.map { StateBadge($0.state) })
            badgeLine("Outcome", SessionOutcome.table.map { StateBadge($0.state) })
            badgeLine("Terminal", TerminalState.table.map { StateBadge($0.state) })
            badgeLine("Account", AccountState.table.map { StateBadge($0.state) })
            badgeLine("Issue", IssueState.table.map { StateBadge($0.state) })
            badgeLine("Run", RunState.table.map { StateBadge($0.state) })
            badgeLine("Unknown", [StateBadge(RunState(rawValue: "paused_by_server"))])
        }
    }

    private func badgeLine(_ name: String, _ items: [StateBadge]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(name).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2).frame(
                width: Space.s8 * 2, alignment: .leading)
            HStack(spacing: Space.s2) { ForEach(items.indices, id: \.self) { items[$0] } }
        }
    }

    private var segmented: some View {
        section("Segmented control") {
            let all = [
                CoreSegment("all", "All"), CoreSegment("run", "Running", symbol: "waveform"),
                CoreSegment("done", "Done"),
            ]
            CoreSegmented("Filter", segments: all, selection: $segment)
            CoreSegmented("Focused", segments: all, selection: $segment).environment(\.coreForcedInteraction, .focused)
            CoreSegmented("Disabled", segments: all, selection: $segment).disabled(true)
            Text("Tab to focus, then arrow keys.").font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
        }
    }

    private var banners: some View {
        section("Connection banner") {
            VStack(spacing: Space.s2) {
                ConnectionBanner(.offline, retry: {})
                ConnectionBanner(.reconnecting)
                ConnectionBanner(.loading)
                ConnectionBanner(.error("The request timed out. Check the server and try again."), retry: {})
            }
        }
    }

    private var overlays: some View {
        section("Toast, sheet and confirm dialog") {
            CoreToast("Session closed", undo: {})
            HStack(spacing: Space.s3) {
                Button("Show toast") { toast = ToastItem("Terminal moved", undo: {}) }.buttonStyle(
                    CoreButtonStyle(.secondary))
                Button("Confirm sheet") { confirm = true }.buttonStyle(CoreButtonStyle(.secondary))
                Button("Destructive confirm") { destructive = true }.buttonStyle(CoreButtonStyle(.secondary))
            }
            CoreConfirmDialog(
                "Close this session?", message: "The agent stops and its work is kept.", confirmTitle: "Close",
                onConfirm: {}, onCancel: {}
            )
            .clipShape(coreShape(Radius.panel))
        }
    }
}
#endif
