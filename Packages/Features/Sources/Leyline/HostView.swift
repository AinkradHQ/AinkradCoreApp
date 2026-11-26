import CoreUI
import Projects
import SwiftUI

/// A host, opened: one page. The overview first (health, pre-set commands, history); the terminal (⏎) and the files (⌘2) open
/// over the whole pane with the way back; Access (⌘,) slides in over the right, like Keys on the map. Esc steps back one
/// level: the panel, the form, the lit card, the terminal or files, then the map.
struct HostView: View {
    let model: LeylineModel
    let host: HostItem
    @State private var state: HostPageState
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.coreAccent) private var paneAccent

    init(model: LeylineModel, host: HostItem) {
        self.model = model
        self.host = host
        _state = State(initialValue: HostPageState(model: model, hostID: host.id))
    }

    private var off: Bool { host.light == .off }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let lease = state.direct {
                    DirectBanner(state: state, lease: lease).padding(.horizontal, Space.s4).padding(.bottom, Space.s3)
                }
                place.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if model.accessOpen {
                AccessPanel(model: model, host: host, state: state)
                    .padding(Space.s3)
                    // The Keys panel's entrance: a few points in from the right and a fade; a fade only under Reduce Motion.
                    .transition(reduce ? .opacity : .opacity.combined(with: .offset(x: Space.s5)))
            }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: model.accessOpen)
        .foregroundStyle(GlassInk.primary)
        .coreFont(size: MacTextSize.body)
        .task {
            async let c: Void = state.loadCommands()
            async let h: Void = state.loadHistory()
            async let k: Void = state.loadHostKeys()
            _ = await (c, h, k)
        }
        .task {
            // The Core stores a probe a minute; the page reads it on the map's beat.
            while !Task.isCancelled {
                await state.loadHealth()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .onAppear { model.page = state }
        .onDisappear {
            state.closePage()
            if model.page === state { model.page = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("host-space")
    }

    @ViewBuilder private var place: some View {
        switch model.section {
        case .terminal:
            HostTerminalTab(model: model, host: host, state: state)
        case .files:
            if let p = state.problem {
                HostProblemCard(problem: p, model: model, hostID: host.id) { await state.loadFiles() }.hostPage()
            } else {
                HostFilesPage(state: state).padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
            }
        case .overview, .access:
            HostOverview(model: model, host: host, state: state)
        }
    }

    // MARK: header

    /// The app header: the way back, the host, its light and route at the left; the terminal (the one prominent tile), files,
    /// access and More at the right. Over the terminal or the files the left side says where you are and leads back.
    private var header: some View {
        AppHeader {
            if model.section == .terminal || model.section == .files {
                back("Back to host", key: model.section == .files ? "esc" : nil) { model.section = .overview }
                    .accessibilityIdentifier("host-back-to-host")
                Text(model.section.title).coreFont(size: MacTextSize.title, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(host.name).foregroundStyle(GlassInk.secondary)
                reach
            } else {
                back(model.layout == .map ? "Map" : "List", key: "esc") { model.closeHost() }
                    .accessibilityIdentifier("host-back")
                Text(host.name).coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
                reach
                route
            }
        } actions: {
            HStack(spacing: Space.s2) {
                if model.section != .terminal {
                    AppActionTile(
                        title: "Terminal", symbol: "terminal", key: "⏎", hue: GlassInk.accent(paneAccent),
                        prominent: true
                    ) { model.go(.terminal) }
                    .disabled(off).opacity(off ? 0.45 : 1)
                    .accessibilityIdentifier("host-open-terminal")
                }
                if model.section != .files {
                    AppActionTile(title: "Files", symbol: "folder", key: "⌘2", hue: GlassInk.accent(paneAccent)) {
                        model.go(.files)
                    }
                    .disabled(off).opacity(off ? 0.45 : 1)
                    .accessibilityIdentifier("host-open-files")
                }
                AppActionTile(title: "Access", symbol: "lock", key: "⌘,", hue: GlassInk.accent(paneAccent)) {
                    model.go(.access)
                }
                .accessibilityIdentifier("host-open-access")
                MoreButton(items: HostMore.items(model, host, state: state))
            }
            // Under the Access panel: hidden, so no edge shows beside it (Esc or the panel's esc closes it).
            .opacity(model.accessOpen ? 0 : 1).allowsHitTesting(!model.accessOpen)
            .accessibilityHidden(model.accessOpen)
        }
    }

    private func back(_ title: String, key: String?, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { Label(title, systemImage: "chevron.left") }
            .buttonStyle(CoreButtonStyle(.plain, size: .small))
            .environment(\.coreKeycap, key)
    }

    /// "Online · 31 ms", "Slow · 182 ms", "Not answering": the Core's last check, as the map draws it.
    @ViewBuilder private var reach: some View {
        if let r = host.reach {
            let ms = r.latencyMS.map { " · \($0) ms" } ?? ""
            switch host.light {
            case .off: StateBadge("Not answering", tone: .queue, symbol: "moon.zzz")
            case .slow: StateBadge("Slow" + ms, tone: .warn, symbol: "tortoise")
            default: StateBadge("Online" + ms, tone: .done, symbol: "checkmark")
            }
        }
    }

    private var route: some View {
        let hops = [host.viaRunner == nil ? "Core" : "Runner"] + model.route(host).dropFirst() + [host.name]
        return HStack(spacing: Space.s1) {
            ForEach(Array(hops.enumerated()), id: \.offset) { i, r in
                if i > 0 {
                    Image(systemName: "arrow.right").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                }
                Text(r).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A failure that stops the whole page, as the Accounts and Connections state card: what is wrong, the fix as the prominent
/// tile, and Try Again.
struct HostProblemCard: View {
    let problem: HostProblem
    let model: LeylineModel
    let hostID: String
    let retry: () async -> Void
    @Environment(\.coreAccent) private var paneAccent

    var body: some View {
        LeylineStateCard(symbol: problem.symbol, title: problem.title, text: problem.line, tone: .warn) {
            switch problem.fix {
            case .access:
                AppActionTile(
                    title: "Open Access", symbol: "lock", key: "⌘,", hue: GlassInk.accent(paneAccent), prominent: true
                ) { model.go(.access) }
            case .none: EmptyView()
            }
            AppActionTile(
                title: "Try Again", symbol: "arrow.clockwise", key: "", hue: GlassInk.accent(paneAccent),
                prominent: problem.fix == .none
            ) {
                model.hostProblem[hostID] = nil
                Task { await retry() }
            }
        }
        .accessibilityIdentifier("host-problem")
    }
}

extension View {
    /// A state in place of a page: at its top, inside the pane's margins, like Accounts and Connections.
    func hostPage() -> some View {
        padding(.horizontal, Space.s4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
