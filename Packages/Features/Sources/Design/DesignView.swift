import CoreUI
import Projects
import Shell
import SwiftUI

/// The Design pane: the home (top bar, category rail, brief composer, the wall of cards) or the open item. Opening and going
/// back cross-fade. The pane draws no background of its own (`own: true`), so the islands sit over the wallpaper, as in the
/// approved mockup (`Designs/core/design/index.html`).
struct DesignView: View {
    let model: DesignModel
    @FocusState private var paneFocus: Bool

    var body: some View {
        ZStack {
            if let item = model.open {
                DesignDetail(model: model, item: item).transition(.opacity)
            } else {
                DesignHome(model: model).transition(.opacity)
            }
        }
        .padding(Space.s2)
        .foregroundStyle(GlassInk.primary)
        .coreFont(size: MacTextSize.body)
        .paneLook(nil, own: true)
        .clipShape(coreShape(Radius.cardMac))
        .focusable()
        .focused($paneFocus)
        .focusEffectDisabled()
        .onAppear { paneFocus = true }
        .retakeFocus(after: model.host.shell, pane: "design") { paneFocus = true }
        .onKeyPress(.escape) {
            guard model.openID != nil else { return .ignored }
            model.closeItem()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("design-pane")
    }
}

struct DesignHome: View {
    let model: DesignModel

    var body: some View {
        VStack(spacing: Space.s2) {
            TopBar(model: model)
            if model.load == .ready { KindFilterRow(model: model) }
            wall
        }
    }

    @ViewBuilder private var wall: some View {
        switch model.load {
        case .loading:
            ScrollView {
                LazyVGrid(columns: DesignWall.columns, spacing: Space.s4) {
                    ForEach(0..<3, id: \.self) { _ in DesignCardSkeleton() }
                }
                .padding(.top, Space.s2)
            }
            .scrollIndicators(.never)
        case .notConnected:
            centered(
                CoreStateCard(
                    symbol: "wifi.slash", title: "Not connected",
                    line: "Designs live on your Core. They show up here once this Mac is connected."))
        case .absent:
            centered(
                CoreStateCard(
                    symbol: "paintbrush.pointed", title: "This Core has no Design",
                    line: "Design arrives with a Core update. Designs and the library show up here after it."))
        case .failed(let why):
            centered(
                CoreStateCard(
                    symbol: "exclamationmark.triangle", title: "Designs did not load", line: why,
                    primary: CoreAction("Try again") { model.resync() }))
        case .ready:
            DesignWall(model: model)
        }
    }

    private func centered<V: View>(_ v: V) -> some View {
        v.frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.s4)
    }
}

/// "Design", what is in it, the Filter field and the way to the design systems.
private struct TopBar: View {
    let model: DesignModel

    var body: some View {
        AppHeader {
            Text("Design").coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
            if model.load == .ready { Text(model.summary).foregroundStyle(GlassInk.secondary) }
        } actions: {
            if model.composeSupported && !model.readOnly {
                Button {
                    Task { await model.drawWithAI() }
                } label: {
                    Label("Draw with AI", systemImage: "sparkles")
                }
                .buttonStyle(CoreButtonStyle(.secondary))
                .help("Make a new design and let AI draw three directions on it")
                .accessibilityIdentifier("design-draw-ai-home")
            }
            Button {
                model.openNew()
            } label: {
                Label("Advanced…", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(CoreButtonStyle(.secondary))
            .help("New design (advanced): name, kind and project")
            .accessibilityIdentifier("design-new-advanced")
            Button {
                Task { await model.quickNew() }
            } label: {
                Label("New design", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.prominent))
            .help("Make a blank design and open it")
            .accessibilityIdentifier("design-new")
        }
        .padding(.top, Space.s2)
        .frame(maxWidth: .infinity)
        .coreWell(radius: Radius.pane)
    }
}

/// The mockup's head row: the kind filter as a segmented control, then the search field (Design, `20-design.html`).
private struct KindFilterRow: View {
    let model: DesignModel
    private static let kinds: [(DesignCategory, String)] = [
        (.all, "All"), (.screens, "Designs"), (.systems, "Design systems"), (.mockups, "Mockups"),
    ]

    var body: some View {
        HStack(spacing: Space.s3) {
            CoreSegmented(
                "Kind",
                segments: Self.kinds.map { CoreSegment($0.0, $0.1) },
                selection: Binding(
                    get: { Self.kinds.contains { $0.0 == model.category } ? model.category : .all },
                    set: { model.pick($0) }))
            Spacer(minLength: 0)
            FilterField(text: Binding(get: { model.filter }, set: { model.filter = $0 }), label: "Search designs")
                .frame(width: Space.s8 * 5)
        }
        .padding(.horizontal, Space.s1)
        .accessibilityIdentifier("design-kind-filter")
    }
}

// The brief composer (describe what AI should design) stays out until AI drawing (E11-4): a disabled copy only looked broken.

/// The wall: on All designs a section per category that has something; on one category its cards; Needs you and Drawing
/// now say what will show there.
struct DesignWall: View {
    let model: DesignModel
    @State private var settled = false
    @State private var width: CGFloat = 0

    /// The skeletons' grid: as many columns of at least 256 pt as fit.
    static let columns = [GridItem(.adaptive(minimum: cardMin), spacing: Space.s4, alignment: .top)]
    static let cardMin = Space.s8 * 6

    /// The page's columns, as Photos and Finder do: as many 256 pt columns as fit the width, the same count for every
    /// section so columns line up from section to section. A short section leaves its trailing slots empty.
    static func columns(width: CGFloat) -> [GridItem] {
        let fit = max(1, Int((width + Space.s4) / (cardMin + Space.s4)))
        return Array(repeating: GridItem(.flexible(), spacing: Space.s4, alignment: .top), count: fit)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s6) {
                content
            }
            // The wall takes the whole width, so the adaptive grid's columns stretch to fill each row.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Space.s2).padding(.bottom, Space.s8)
        }
        .scrollIndicators(.never)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .onAppear { settled = true }
    }

    @ViewBuilder private var content: some View {
        switch model.category {
        case .needsYou:
            empty(
                "tray", "Nothing needs you",
                "Designs waiting for your review, your notes or your approval show here.")
        case .drawing:
            empty("pencil", "Nothing is being drawn", "When AI draws a design you can watch it here, live.")
        default:
            grid(model.items(in: model.category))
        }
    }

    /// The mockup's one grid: the "New design" card first, then the designs. A search or kind with no match says so.
    private func grid(_ list: [DesignItem]) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            if width > 0 {
                LazyVGrid(columns: Self.columns(width: width), spacing: Space.s4) {
                    NewDesignCard(model: model, settled: settled)
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                        DesignCard(model: model, item: item, index: i + 1, settled: settled)
                    }
                }
                .frame(maxWidth: .infinity)
                .transaction { $0.animation = nil }
            }
            if list.isEmpty {
                Text("No designs match. Try another word, or start a new design.")
                    .foregroundStyle(GlassInk.secondary).padding(.horizontal, Space.s1)
            }
        }
    }

    private func empty(_ symbol: String, _ title: String, _ line: String) -> some View {
        CoreStateCard(symbol: symbol, title: title, line: line)
            .frame(maxWidth: .infinity).padding(.top, Space.s8)
    }
}
