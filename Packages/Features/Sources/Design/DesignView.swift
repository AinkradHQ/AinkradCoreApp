import CoreUI
import Projects
import Shell
import SwiftUI

/// The Design pane: the home (pages, find, the wall of pictures, the key line) or the open item. Opening and going back
/// cross-fade. The pane's surface follows the Look (Settings, Appearance, or Design's own), like Leyline and Lore. Every
/// action has a key (`DesignKeys.swift`).
struct DesignView: View {
    let model: DesignModel
    @FocusState private var paneFocus: Bool
    @FocusState private var findFocus: Bool

    var body: some View {
        ZStack {
            if let item = model.open {
                DesignDetail(model: model, item: item).transition(.opacity)
            } else {
                DesignHome(model: model, findFocus: $findFocus).transition(.opacity)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .coreFont(size: MacTextSize.body)
        .paneLook(AppLookPrefs.shared("design").look)
        .appLookTheme(AppLookPrefs.shared("design"))
        .clipShape(coreShape(Radius.cardMac))
        .focusable()
        .focused($paneFocus)
        .focusEffectDisabled()
        .onAppear { paneFocus = true }
        .retakeFocus(after: model.host.shell, pane: "design") { paneFocus = true }
        .onKeyPress(phases: .down) { model.key($0, find: $findFocus) }
        .onChange(of: model.openID) { _, _ in
            findFocus = false
            paneFocus = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("design-pane")
    }
}

struct DesignHome: View {
    let model: DesignModel
    var findFocus: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 0) {
            DesignHeader(model: model, findFocus: findFocus)
            if model.load == .ready, model.category.page == .library {
                DesignSubRow(model: model).padding(.horizontal, Space.s4).padding(.bottom, Space.s3)
                    .transition(.opacity)
            }
            wall.frame(maxWidth: .infinity, maxHeight: .infinity)
            DesignFooter(model: model)
        }
        .animation(Motion.out(Motion.ui), value: model.category.page == .library)
    }

    @ViewBuilder private var wall: some View {
        switch model.load {
        case .loading:
            ScrollView {
                LazyVGrid(columns: DesignWall.columns, spacing: Space.s5) {
                    ForEach(0..<6, id: \.self) { _ in DesignCardSkeleton() }
                }
                .padding(.horizontal, Space.s4).padding(.top, Space.s1)
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
            if model.items.isEmpty {
                centered(
                    CoreStateCard(
                        symbol: "paintbrush.pointed", title: "Nothing designed yet",
                        line: "Start a blank canvas, or describe a screen and let AI draw three directions.",
                        primary: model.readOnly ? nil : CoreAction("New design") { Task { await model.quickNew() } }))
            } else {
                DesignWall(model: model)
            }
        }
    }

    private func centered<V: View>(_ v: V) -> some View {
        v.frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.s4)
    }
}

/// The app header every pane uses: the pages at the left (⌘1…⌘5, with counts), find, Draw with AI and New at the right.
private struct DesignHeader: View {
    let model: DesignModel
    var findFocus: FocusState<Bool>.Binding
    @Environment(\.coreAccent) private var paneAccent

    var body: some View {
        AppHeader {
            ForEach(Array(DesignCategory.pages.enumerated()), id: \.element) { i, page in
                AppFilterTile(
                    title: page.short, count: model.load == .ready ? model.count(page) : -1,
                    on: model.category.page == page, key: "⌘\(i + 1)"
                ) { model.pick(page) }
                .accessibilityIdentifier("design-tab-\(page.rawValue)")
            }
        } actions: {
            if let p = model.project {
                Button {
                    withAnimation(Motion.out(Motion.ui)) { model.project = nil }
                } label: {
                    Label(model.projectName(p), systemImage: "xmark")
                }
                .buttonStyle(CoreButtonStyle(.secondary))
                .help("Show every project again")
                .accessibilityIdentifier("design-project-chip")
            }
            DesignFind(text: Binding(get: { model.filter }, set: { model.filter = $0 }), focus: findFocus)
            if model.composeSupported && !model.readOnly {
                AppActionTile(title: "Draw with AI", symbol: "sparkles", key: "", hue: GlassInk.accent(paneAccent)) {
                    Task { await model.drawWithAI() }
                }
                .help("Make a new design and let AI draw three directions on it")
                .accessibilityIdentifier("design-draw-ai-home")
            }
            Button {
                model.openNew()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(CoreButtonStyle(.secondary))
            .keyboardShortcut("n", modifiers: [.command, .option])
            .help("New design (advanced): name, kind and project  ⌥⌘N")
            .accessibilityLabel("New design, advanced")
            .disabled(model.readOnly)
            .accessibilityIdentifier("design-new-advanced")
            AppActionTile(
                title: "New", symbol: "plus", key: "⌘N", hue: GlassInk.accent(paneAccent), prominent: true
            ) { Task { await model.quickNew() } }
            .disabled(model.readOnly)
            .accessibilityIdentifier("design-new")
        }
    }
}

/// Under the header on Library: the library's kinds.
private struct DesignSubRow: View {
    let model: DesignModel

    var body: some View {
        HStack(spacing: Space.s2) {
            if model.category.page == .library {
                tile(.library, "Everything")
                ForEach(DesignCategory.libraryKinds) { tile($0, $0.short) }
            }
            Spacer(minLength: 0)
        }
    }

    private func tile(_ c: DesignCategory, _ title: String) -> some View {
        AppFilterTile(title: title, count: model.count(c), on: model.category == c, key: "") { model.pick(c) }
            .accessibilityIdentifier("design-kind-\(c.rawValue)")
    }
}

/// "Find a design" with ⌘F on it; Esc clears it, then gives the keys back to the wall.
private struct DesignFind: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass").coreFont(size: MacTextSize.body, weight: .medium)
                .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            TextField("", text: $text, prompt: Text("Find a design").foregroundStyle(GlassInk.secondary))
                .textFieldStyle(.plain).focused(focus)
                .accessibilityLabel("Find a design")
                .accessibilityIdentifier("design-find")
            if text.isEmpty {
                CoreKeycap("⌘F")
            } else {
                CoreIconButton(symbol: "xmark", label: "Clear") { text = "" }
            }
        }
        .padding(.horizontal, Space.s3).frame(width: Space.s8 * 8, height: MacSize.controlLg)
        .coreFieldSurface(focused: focus.wrappedValue)
        .onExitCommand {
            if text.isEmpty { focus.wrappedValue = false } else { text = "" }
        }
    }
}

/// The foot of the page, as in Leyline and Terminals: what is here at the left, the keys at the right.
private struct DesignFooter: View {
    let model: DesignModel
    @Environment(\.coreAccent) private var paneAccent

    var body: some View {
        HStack(spacing: Space.s4) {
            if model.load == .ready, !model.items.isEmpty {
                HStack(spacing: Space.s2) {
                    let designs = model.docs.filter { $0.kind == .design }.count
                    AppStatChip("rectangle.on.rectangle", Words.count(designs, "design"), GlassInk.accent(paneAccent))
                    let systems = model.docs.filter { $0.kind == .system }.count
                    AppStatChip("swatchpalette", Words.count(systems, "system"), GlassInk.slate)
                    AppStatChip(
                        "macwindow", Words.count(model.docs.count - designs - systems, "mockup"), GlassInk.slate)
                    AppStatChip(
                        "photo.on.rectangle", Words.count(model.assets.count + model.kits.count, "library item"),
                        GlassInk.slate)
                }
            }
            Spacer(minLength: 0)
            if model.load == .ready, !model.items.isEmpty {
                hint("↑↓←→", "Move")
                hint("⏎", "Open")
                hint("⌘N", "New")
                hint("type", "Find")
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
    }

    private func hint(_ keys: String, _ what: String) -> some View {
        HStack(spacing: Space.s2) {
            CoreKeycap(keys)
            Text(what).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The wall: on Library's Everything a section per kind that has something; elsewhere one grid, newest first. The keys
/// move a soft light over it.
struct DesignWall: View {
    let model: DesignModel
    @State private var settled = false
    @State private var width: CGFloat = 0

    /// The skeletons' grid: as many columns of at least 192 pt as fit.
    static let columns = [GridItem(.adaptive(minimum: cardMin), spacing: Space.s4, alignment: .top)]
    static let cardMin = Space.s8 * 6

    /// The page's columns, as Photos and Finder do: as many 192 pt columns as fit the width, the same count for every
    /// section so columns line up from section to section.
    static func columns(width: CGFloat) -> [GridItem] {
        let fit = max(1, Int((width + Space.s4) / (cardMin + Space.s4)))
        return Array(repeating: GridItem(.flexible(), spacing: Space.s4, alignment: .top), count: fit)
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s6) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.s4).padding(.top, Space.s1).padding(.bottom, Space.s6)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selected) { _, id in
                guard let id else { return }
                withAnimation(Motion.out(Motion.ui)) { reader.scrollTo(id) }
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width - Space.s4 * 2
        } action: {
            width = $0
            model.columns = Self.columns(width: $0).count
        }
        .onAppear { settled = true }
    }

    @ViewBuilder private var content: some View {
        let list = model.shown
        if list.isEmpty {
            CoreStateCard(
                symbol: model.filter.isEmpty ? model.category.symbol : "magnifyingglass",
                title: model.filter.isEmpty ? "No \(model.category.title.lowercased()) yet" : "No match",
                line: model.filter.isEmpty
                    ? "What you make or add here shows up as a picture."
                    : "Nothing is called “\(model.filter)”. Try another word."
            )
            .frame(maxWidth: .infinity).padding(.top, Space.s8)
        } else if model.category == .library, model.filter.isEmpty {
            ForEach(DesignCategory.libraryKinds) { kind in
                let part = list.filter { $0.category == kind }
                if !part.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        Text(kind.title).coreFont(size: MacTextSize.headline, weight: .semibold)
                            .accessibilityAddTraits(.isHeader)
                        grid(part, from: list)
                    }
                }
            }
        } else {
            grid(list, from: list)
        }
    }

    @ViewBuilder private func grid(_ part: [DesignItem], from list: [DesignItem]) -> some View {
        if width > 0 {
            LazyVGrid(columns: Self.columns(width: width), spacing: Space.s5) {
                ForEach(part) { item in
                    DesignCard(
                        model: model, item: item, index: list.firstIndex(of: item) ?? 0, settled: settled
                    )
                    .id(item.id)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
