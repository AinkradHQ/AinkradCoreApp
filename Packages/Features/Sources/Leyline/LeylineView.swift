import CoreUI
import Projects
import Shell
import SwiftUI

/// The Leyline pane: the hosts gallery, the Keys page, or the open host's space. Opening and going back cross-fade: the screens
/// share no element that could travel. The pane draws no background of its own (`own: true`), so the cards sit over the wallpaper.
struct LeylineView: View {
    let model: LeylineModel
    @FocusState private var paneFocus: Bool

    var body: some View {
        ZStack {
            if let host = model.open {
                HostSpaceView(model: model, host: host).transition(.opacity)
            } else {
                LeylineHome(model: model).transition(.opacity)
            }
        }
        .appLook(AppLookPrefs.shared("leyline"))
        .clipShape(coreShape(Radius.cardMac))
        .focusable()
        .focused($paneFocus)
        .focusEffectDisabled()
        .onAppear { paneFocus = true }
        .retakeFocus(after: model.host.shell, pane: "leyline") { paneFocus = true }
        .onKeyPress(.escape) {
            if model.quickOpen {
                model.quickOpen = false
                return .handled
            }
            if model.openID != nil {
                // Inside a page behind Advanced, Esc goes back to the host's cards first.
                if model.section != .overview { model.section = .overview } else { model.closeHost() }
                return .handled
            }
            return .ignored
        }
        .coreSideKeys { move($0) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.return) {
            guard model.openID == nil, model.page == .hosts, !model.quickOpen, let id = model.cursor else {
                return .ignored
            }
            model.openHost(id)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("leyline-pane")
    }

    /// Arrow keys step the cursor through the gallery's cards in reading order.
    private func move(_ step: Int) -> KeyPress.Result {
        guard model.openID == nil, model.page == .hosts, !model.quickOpen else { return .ignored }
        let ids = model.groups.flatMap(\.hosts).map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let at = model.cursor.flatMap { ids.firstIndex(of: $0) }
        let next = at.map { min(max($0 + step, 0), ids.count - 1) } ?? (step > 0 ? 0 : ids.count - 1)
        model.cursor = ids[next]
        return .handled
    }
}

/// The top bar and the page it picks: Hosts or Keys.
struct LeylineHome: View {
    let model: LeylineModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppHeader {
                Text("Leyline").coreFont(size: MacTextSize.large, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                // TODO(Y9-04): the Fleet page joins Hosts and Keys here.
                CoreSegmented(
                    "Page", segments: LeylinePage.allCases.map { CoreSegment($0, $0.title) },
                    selection: Binding(get: { model.page }, set: { model.page = $0 })
                )
                .fixedSize()
            } actions: {
                if model.load == .ready {
                    Text(summary).foregroundStyle(GlassInk.secondary)
                }
                if model.page == .hosts {
                    FilterField(text: Binding(get: { model.filter }, set: { model.filter = $0 }), label: "Filter hosts")
                }
                Button {
                    model.newHost()
                } label: {
                    Label("Add Host", systemImage: "plus")
                }
                .buttonStyle(CoreButtonStyle(.prominent))
                .disabled(model.readOnly || model.load != .ready)
                .help("Add Host  ⌘N")
                .accessibilityIdentifier("leyline-add-host")
            }
            switch model.page {
            case .hosts: HostsGallery(model: model)
            case .keys: KeysPage(model: model)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .coreFont(size: MacTextSize.body)
        .overlay(alignment: .topTrailing) { quick }
        .overlay(alignment: .bottom) { if model.page == .hosts { FleetBar(model: model) } }
        .animation(Motion.out(Motion.ui), value: model.quickOpen)
        .animation(Motion.out(Motion.ui), value: model.selection.isEmpty)
    }

    private var summary: String {
        let h = Words.count(model.hosts.count, "host")
        return model.page == .hosts ? h : "\(Words.count(model.keys.count, "key")) · \(h)"
    }

    @ViewBuilder private var quick: some View {
        if model.quickOpen {
            ZStack(alignment: .topTrailing) {
                // A click anywhere else closes it, like any pop-over.
                Color.clear.contentShape(Rectangle()).onTapGesture { model.quickOpen = false }
                QuickAddHost(model: model)
                    .padding(.trailing, Space.s4).padding(.top, Space.s8 + Space.s5)
                    .transition(.opacity)
            }
        }
    }
}

/// The gallery: hosts grouped by project or group, each a card.
struct HostsGallery: View {
    let model: LeylineModel
    @State private var settled = false

    var body: some View {
        content.onAppear { settled = true }
    }

    @ViewBuilder private var content: some View {
        switch model.load {
        case .loading:
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: Space.s4) {
                    ForEach(0..<3, id: \.self) { _ in HostCardSkeleton() }
                }
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
            }
            .scrollIndicators(.never)
        case .notConnected:
            centered(
                CoreStateCard(
                    symbol: "wifi.slash", title: "Not connected",
                    line: "Hosts live on your Core. They show up here once this Mac is connected."))
        case .absent:
            centered(
                CoreStateCard(
                    symbol: "point.3.connected.trianglepath.dotted", title: "This Core has no Leyline",
                    line: "Leyline arrives with a Core update. Hosts and keys show up here after it."))
        case .failed(let why):
            centered(
                CoreStateCard(
                    symbol: "exclamationmark.triangle", title: "Hosts did not load", line: why,
                    primary: CoreAction("Try again") { model.resync() }))
        case .ready:
            if model.hosts.isEmpty {
                centered(
                    CoreStateCard(
                        symbol: "server.rack", title: "No hosts yet",
                        line: "Type user@address and press Return. Leyline asks before it does anything on a host.",
                        primary: CoreAction("Add Host") { model.newHost() }))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        ForEach(model.groups) { group in section(group) }
                        if !model.filter.isEmpty, model.shown.isEmpty {
                            Text("No host matches “\(model.filter)”.").foregroundStyle(GlassInk.secondary)
                                .frame(maxWidth: .infinity)
                        } else if model.filter.isEmpty, model.shown.isEmpty {
                            Text("No host fits “\(LeylineOptions.current.title)”. Change it in Settings, Leyline, Options.")
                                .foregroundStyle(GlassInk.secondary).frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, Space.s4).padding(.bottom, Space.s8 * 3)
                }
                .scrollIndicators(.never)
            }
        }
    }

    private func section(_ group: HostGroup) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(group.title).coreFont(size: MacTextSize.headline, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(group.sub).foregroundStyle(GlassInk.secondary)
            }
            .padding(.horizontal, Space.s1)
            LazyVGrid(columns: Self.columns, spacing: Space.s4) {
                ForEach(Array(group.hosts.enumerated()), id: \.element.id) { i, h in
                    HostCard(model: model, host: h, index: i, settled: settled)
                }
            }
        }
    }

    /// Wide cards: three to a row on a full-size pane.
    static let columns = [
        GridItem(.adaptive(minimum: Space.s8 * 15, maximum: Space.s8 * 20), spacing: Space.s4, alignment: .top)
    ]

    private func centered<V: View>(_ v: V) -> some View {
        v.frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.s4)
    }
}

/// What a fleet run needs once hosts are ticked. TODO(Y4-03): the run, the output grid and the one fleet approval; until then
/// the bar shows the count and says so.
struct FleetBar: View {
    let model: LeylineModel

    var body: some View {
        if !model.selection.isEmpty {
            HStack(spacing: Space.s3) {
                Text(Words.count(model.selection.count, "host")).coreFont(
                    size: MacTextSize.body, weight: .semibold)
                Text("Running a command on several hosts arrives with the fleet update.")
                    .foregroundStyle(GlassInk.secondary).lineLimit(1)
                Spacer(minLength: Space.s3)
                Soon(prominent: true, help: "Fleet runs arrive with the next update") {
                    Label("Run", systemImage: "play")
                }
                CoreIconButton(symbol: "xmark", label: "Clear the selection") { model.selection = [] }
            }
            .corePanel(radius: Radius.panel, padding: Space.s3)
            .frame(maxWidth: Space.s8 * 22)
            .padding(Space.s4)
            .transition(.opacity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("leyline-fleet-bar")
        }
    }
}
