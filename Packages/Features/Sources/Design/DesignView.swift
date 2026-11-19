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
            HStack(alignment: .top, spacing: Space.s2) {
                CategoryRail(model: model).frame(width: Space.s8 * 7 + Space.s2)
                wall
            }
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
            FilterField(text: Binding(get: { model.filter }, set: { model.filter = $0 }), label: "Filter designs")
            Button {
                model.pick(.systems)
            } label: {
                Label("Design systems", systemImage: DesignCategory.systems.symbol)
            }
            .buttonStyle(CoreButtonStyle(.secondary))
            .help("Show the design systems")
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

/// The rail: Needs you, Drawing now, All designs; the kinds; the projects with something in them.
/// TODO(design-system): proposal CoreNavRow (a flat rail row, filled only when selected or hovered, as in the mockup);
/// until then the rail uses `CoreRow`, whose rows sit on the glass-card fill.
private struct CategoryRail: View {
    let model: DesignModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach([DesignCategory.needsYou, .drawing, .all]) { row($0) }
                Color.clear.frame(height: Space.s2)
                ForEach(DesignCategory.kinds) { row($0) }
                if !model.railProjects.isEmpty {
                    Text("Projects").coreFont(size: MacTextSize.meta, weight: .semibold)
                        .foregroundStyle(GlassInk.secondary)
                        .padding(.horizontal, Space.s3).padding(.top, Space.s4).padding(.bottom, Space.s1)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(model.railProjects, id: \.ref.id) { p in
                        CoreRow(
                            p.ref.name, symbol: "folder", selected: model.project == p.ref.id,
                            action: { model.pickProject(p.ref.id) }
                        ) { CountBadge(p.count, tone: .quiet, showsZero: true) }
                        .help(
                            model.project == p.ref.id ? "Show every project" : "Only what is related to \(p.ref.name)")
                    }
                }
            }
            .padding(Space.s2)
        }
        .scrollIndicators(.never)
        .frame(maxHeight: .infinity)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("design-rail")
    }

    private func row(_ c: DesignCategory) -> some View {
        let n = model.count(c)
        return CoreRow(
            c.title, symbol: c.symbol, selected: model.project == nil && model.category == c, action: { model.pick(c) }
        ) {
            CountBadge(n, tone: c == .needsYou && n > 0 ? .needsYou : .quiet, showsZero: true)
        }
        .accessibilityIdentifier("design-rail-\(c.rawValue)")
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
    static let cardMin = Space.s8 * 8

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
        case .all:
            let sections = DesignCategory.kinds.map { ($0, model.items(in: $0)) }.filter { !$0.1.isEmpty }
            if sections.isEmpty {
                emptyLibrary
            } else {
                if let p = model.project {
                    // A project row is the rail's one selection: its name and count head the wall.
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(model.projectName(p)).coreFont(size: MacTextSize.title, weight: .semibold)
                            .accessibilityAddTraits(.isHeader)
                        Text("· \(model.items(in: .all).count)").foregroundStyle(GlassInk.secondary)
                    }
                    .padding(.horizontal, Space.s1)
                }
                ForEach(sections, id: \.0) { c, list in section(c.title, sub: nil, list) }
            }
        default:
            let list = model.items(in: model.category)
            if list.isEmpty {
                emptyLibrary
            } else {
                section(model.category.title, sub: model.project.map(model.projectName) ?? "all projects", list)
            }
        }
    }

    @ViewBuilder private var emptyLibrary: some View {
        if !model.filter.isEmpty {
            Text("Nothing matches “\(model.filter)”.").foregroundStyle(GlassInk.secondary)
                .frame(maxWidth: .infinity).padding(.top, Space.s8)
        } else {
            // Designs, design systems and mockups can be made here; the library's files only arrive from elsewhere.
            let makes = [.all, .screens, .systems, .mockups].contains(model.category)
            CoreStateCard(
                symbol: model.category.symbol, title: makes ? "Nothing designed yet" : "Nothing here yet",
                line: makes
                    ? "Start with a blank canvas. Logos, icons and fonts land in the library when AI sessions or other devices add them."
                    : "Designs, logos, icons and fonts land here when AI sessions or other devices add them to the Core.",
                secondary: makes ? CoreAction("New design (advanced)…") { model.openNew() } : nil,
                primary: makes ? CoreAction("New design") { Task { await model.quickNew() } } : nil
            )
            .frame(maxWidth: .infinity).padding(.top, Space.s8)
        }
    }

    private func empty(_ symbol: String, _ title: String, _ line: String) -> some View {
        CoreStateCard(symbol: symbol, title: title, line: line)
            .frame(maxWidth: .infinity).padding(.top, Space.s8)
    }

    private func section(_ title: String, sub: String?, _ list: [DesignItem]) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(title).coreFont(size: MacTextSize.headline, weight: .semibold).accessibilityAddTraits(.isHeader)
                if let sub { Text(sub).foregroundStyle(GlassInk.secondary) }
            }
            .padding(.horizontal, Space.s1)
            // Laid out once the width is known, and never animated between column counts (a resize re-flows at once).
            if width > 0 {
                LazyVGrid(columns: Self.columns(width: width), spacing: Space.s4) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                        DesignCard(model: model, item: item, index: i, settled: settled)
                    }
                }
                .frame(maxWidth: .infinity)
                .transaction { $0.animation = nil }
            }
        }
    }
}
