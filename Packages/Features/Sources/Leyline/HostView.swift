import CoreUI
import Projects
import SwiftUI

/// A host, opened: a bar with the way back (Esc), its name, light and route, and the tabs Terminal ⌘1, Files ⌘2, History
/// ⌘3, Access ⌘,; under it the tab, with the host's load beside it. Return from the map lands on the terminal.
struct HostView: View {
    let model: LeylineModel
    let host: HostItem
    @State private var state: HostPageState

    init(model: LeylineModel, host: HostItem) {
        self.model = model
        self.host = host
        _state = State(initialValue: HostPageState(model: model, hostID: host.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bar
            if let lease = state.direct {
                DirectBanner(state: state, lease: lease).padding(.horizontal, Space.s4).padding(.bottom, Space.s3)
            }
            HStack(spacing: 0) {
                page.frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.section == .terminal { side }
            }
            .clipShape(coreShape(Radius.cardMac))
            .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
        }
        .foregroundStyle(GlassInk.primary)
        .coreFont(size: MacTextSize.body)
        .task {
            async let c: Void = state.loadCommands()
            async let h: Void = state.loadHistory()
            _ = await (c, h)
        }
        .onDisappear { state.closePage() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("host-space")
    }

    /// The app header: the way back, the host and its route at the left; its tabs and More at the right, the same tiles
    /// as every app's pages.
    private var bar: some View {
        AppHeader {
            Button {
                model.closeHost()
            } label: {
                Label(model.layout == .map ? "Map" : "List", systemImage: "chevron.left")
            }
            .buttonStyle(CoreButtonStyle(.plain, size: .small))
            .environment(\.coreKeycap, "esc")
            .accessibilityIdentifier("host-back")
            Text(host.name).coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
            if let w = host.latencyWord {
                StateBadge(w, tone: host.light == .slow ? .warn : host.light == .off ? .queue : .run, symbol: "circle")
            }
            HStack(spacing: Space.s1) {
                ForEach(Array(route.enumerated()), id: \.offset) { i, r in
                    if i > 0 {
                        Image(systemName: "arrow.right").coreFont(size: MacTextSize.meta)
                            .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                    }
                    Text(r).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        } actions: {
            HStack(spacing: Space.s2) {
                ForEach(HostSection.tabs) { t in
                    AppFilterTile(title: t.title, count: -1, on: model.section == t, key: t.keyWord) {
                        model.section = t
                    }
                    .accessibilityIdentifier("tab-\(t.title)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Host tabs")
            MoreButton(items: HostMore.items(model, host, state: state))
        }
    }

    private var route: [String] {
        [host.viaRunner == nil ? "Core" : "Runner"] + model.route(host).dropFirst() + [host.name]
    }

    @ViewBuilder private var page: some View {
        switch model.section {
        case .terminal: HostTerminalTab(model: model, host: host)
        case .files: HostFilesPage(state: state)
        case .history: HostHistoryPage(state: state)
        case .access: AccessPage(model: model, host: host, state: state)
        case .commands: HostCommandsPage(state: state)
        }
    }

    /// Beside the terminal: CPU, memory and disk, and the last thing that happened. Each hides when the Core has no number.
    private var side: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let h = model.healthByHost[host.id] {
                Grid(alignment: .leading, horizontalSpacing: Space.s2 + 2, verticalSpacing: Space.s2 - 2) {
                    ForEach([("CPU", h.cpuPct), ("Memory", h.memPct), ("Disk", h.diskPct)], id: \.0) { n, v in
                        if let v {
                            GridRow {
                                Text(n).frame(width: Space.s8 + Space.s3, alignment: .leading)
                                LoadBar(percent: v)
                                Text("\(Int(v.rounded()))%").monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            if let e = model.activity[host.id]?.first {
                Text("\(HostPeek.say(e)) · \(HostWords.ago(e.at))").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(width: Space.s8 * 8 + Space.s1, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(GlassInk.well)
    }
}
