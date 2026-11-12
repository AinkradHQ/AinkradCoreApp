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
    @State private var fieldText = "linux-01"
    @State private var selectPick = "claude"
    private static let selectOptions = [
        CoreSelectOption("claude", "Claude Code", symbol: "sparkle", note: "default"),
        CoreSelectOption("codex", "Codex", symbol: "chevron.left.forwardslash.chevron.right"),
        CoreSelectOption("opencode", "OpenCode", symbol: "terminal"),
    ]
    @State private var checks: Set<String> = ["read", "terminal"]

    private let officialOnly: Bool
    private let scrollToOfficial: Bool

    /// `officialOnly` shows just the Official Liquid Glass section (snapshot mode).
    public init(officialOnly: Bool = false, scrollToOfficial: Bool = false) {
        self.officialOnly = officialOnly
        self.scrollToOfficial = scrollToOfficial
    }

    private var palette: Palette { scheme == .dark ? .night : .day }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s6) {
                    Text("CoreUI Gallery").coreFont(size: MacTextSize.large, weight: .semibold)
                    if !officialOnly { ownComponents }
                    #if os(macOS)
                    if #available(macOS 26, *) { OfficialGlassSection().id("official") }
                    #endif
                }
                .padding(Space.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task { if scrollToOfficial { proxy.scrollTo("official", anchor: .top) } }
        }
        .background(LinearGradient(colors: [palette.surface, palette.bg], startPoint: .top, endPoint: .bottom))
        .coreTheme()
        .coreToast($toast)
        .coreConfirm(
            "Close this session?", isPresented: $confirm, message: "The AI session stops and its work is kept.",
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

    @ViewBuilder private var ownComponents: some View {
        buttons
        surfaces
        rows
        badges
        fields
        segmented
        banners
        overlays
        stateCards
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title).coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var buttons: some View {
        section("Buttons") {
            let states: [(String, CoreInteraction?)] = [
                ("Rest", nil), ("Hover", .hover), ("Pressed", .pressed), ("Focus", .focused),
            ]
            ForEach([CoreButtonKind.prominent, .secondary, .plain, .danger], id: \.self) { kind in
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
            Text(name).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).frame(
                width: Space.s8 * 2, alignment: .leading)
            HStack(spacing: Space.s2) { ForEach(items.indices, id: \.self) { items[$0] } }
        }
    }

    private var fields: some View {
        section("Text field, text area, select and checkbox") {
            HStack(alignment: .top, spacing: Space.s4) {
                CoreTextField("Rest", placeholder: "Device name", text: $fieldText)
                CoreTextField("Hover", placeholder: "Device name", text: $fieldText)
                    .environment(\.coreForcedInteraction, .hover)
                CoreTextField("Focus", placeholder: "Device name", text: $fieldText)
                    .environment(\.coreForcedInteraction, .focused)
                CoreTextField("Error", placeholder: "Device name", text: $fieldText, error: "Use 1 to 64 characters.")
                CoreTextField("Disabled", placeholder: "Device name", text: $fieldText).disabled(true)
            }
            HStack(alignment: .top, spacing: Space.s4) {
                CoreTextField("Code", placeholder: "ainkrad-pair:v1?", text: $fieldText, mono: true, suffix: ":443")
                CoreTextField("Large", placeholder: "K7QD", text: $fieldText, mono: true, big: true)
            }
            HStack(alignment: .top, spacing: Space.s4) {
                CoreTextArea("Prompt", placeholder: "What should the AI session do?", text: $fieldText)
                CoreTextArea("Focus", placeholder: "What should the AI session do?", text: $fieldText)
                    .environment(\.coreForcedInteraction, .focused)
            }
            HStack(alignment: .top, spacing: Space.s4) {
                CoreSelect("Select", selection: $selectPick, options: Self.selectOptions)
                CoreSelect("Hover", selection: $selectPick, options: Self.selectOptions)
                    .environment(\.coreForcedInteraction, .hover)
                CoreSelect("Open", selection: $selectPick, options: Self.selectOptions)
                    .environment(\.coreForcedInteraction, .focused)
                CoreSelect("Error", selection: $selectPick, options: Self.selectOptions, error: "Pick a runner.")
                CoreSelect("Disabled", selection: $selectPick, options: Self.selectOptions).disabled(true)
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                ForEach(["read", "approve", "terminal"], id: \.self) { name in
                    CoreCheckbox(
                        name, detail: "What this scope allows", isOn: checkBinding(name), mono: true)
                }
                CoreCheckbox("Disabled", detail: "Not available here", isOn: checkBinding("admin")).disabled(true)
            }
        }
    }

    private func checkBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { checks.contains(name) },
            set: { if $0 { checks.insert(name) } else { checks.remove(name) } })
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
            Text("Tab to focus, then arrow keys.").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
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

    private var stateCards: some View {
        section("State card, dialog footer, skeleton, chips") {
            CoreStateCard(
                symbol: "tray", title: "Nothing here yet", line: "Sessions you start show up here.",
                secondary: CoreAction("Learn more") {}, primary: CoreAction("New session") {})
            CoreDialogFooter(
                cancel: CoreAction("Cancel", key: .cancel) {}, primary: CoreAction("Save", key: .primary) {})
            HStack(spacing: Space.s3) {
                CoreSkeleton().frame(width: 160, height: 28)
                CoreSkeleton(coreShape(Radius.cardMac)).frame(width: 120, height: 48)
                CoreChip("Needs a look", symbol: "exclamationmark.triangle")
                CoreChip("2\u{00A0}ms")
            }
            HStack {
                CoreBusyBar().frame(width: 240)
                Text("A very long title that has to shrink before its badge does").lineLimit(1)
                StateBadge("Needs a look", tone: .warn, symbol: "exclamationmark.triangle")
            }
            GlassToggleTile(
                "An approval is waiting", sub: "Neutral well, the switch carries on.", symbol: "hand.raised",
                isOn: .constant(true), fill: true)
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
                "Close this session?", message: "The AI session stops and its work is kept.", confirmTitle: "Close",
                onConfirm: {}, onCancel: {}
            )
            .clipShape(coreShape(Radius.panel))
        }
    }
}
#endif
