import CoreUI
import Shell
import SwiftUI

/// The Projects pane: the gallery, or the open project's space. Opening and going back cross-fade: the two screens share no
/// element that could travel. The pane draws no background of its own (`own: true`), so the cards sit over the wallpaper.
struct ProjectsView: View {
    let model: ProjectsModel
    @FocusState private var paneFocus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// Opening: the gallery fades out and settles back a touch; the space comes in from just above full size. Going back, the
    /// gallery fades in. Under Reduce Motion every one of these is a fade.
    private var spaceIn: AnyTransition {
        reduce
            ? .opacity.animation(Motion.out(Motion.hover))
            : .opacity.combined(with: .scale(scale: 1.01)).animation(Motion.expo(Motion.move))
    }
    private var galleryOut: AnyTransition {
        reduce
            ? .opacity.animation(Motion.out(Motion.hover))
            : .opacity.combined(with: .scale(scale: 0.985)).animation(Motion.exit(0.15))
    }

    var body: some View {
        ZStack {
            if let project = model.open {
                ProjectSpaceView(model: model, project: project)
                    .transition(.asymmetric(insertion: spaceIn, removal: .opacity.animation(Motion.exit(0.15))))
            } else {
                GalleryView(model: model)
                    .transition(
                        .asymmetric(insertion: .opacity.animation(Motion.out(Motion.ui)), removal: galleryOut))
            }
        }
        // Like every app: the pane draws Settings › Appearance (blur, transparency), or the Projects own Look.
        .paneLook(AppLookPrefs.shared("projects").look)
        .appLookTheme(AppLookPrefs.shared("projects"))
        .clipShape(coreShape(Radius.cardMac))
        .focusable()
        .focused($paneFocus)
        .focusEffectDisabled()
        .onAppear { paneFocus = true }
        .retakeFocus(after: model.host.shell, pane: "projects") { paneFocus = true }
        .onKeyPress(.escape) {
            if model.openID != nil {
                model.closeProject()
                return .handled
            }
            return model.clearGalleryState() ? .handled : .ignored
        }
        .coreSideKeys { move($0) }
        .onKeyPress(.upArrow) { move(-model.galleryColumns) }
        .onKeyPress(.downArrow) { move(model.galleryColumns) }
        .onKeyPress(.return) {
            guard model.openID == nil, let id = model.cursor else { return .ignored }
            model.openProject(id)
            return .handled
        }
        .onKeyPress(phases: .down) { typed($0) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projects-pane")
    }

    /// Arrow keys step the cursor through the gallery's cards: a card for left and right, a row for up and down.
    private func move(_ step: Int) -> KeyPress.Result {
        guard model.openID == nil, !model.shown.isEmpty else { return .ignored }
        model.moveCursor(by: step)
        return .handled
    }

    /// ⌘F asks for the Filter; typing a letter in the gallery starts filtering and Delete takes one back.
    private func typed(_ press: KeyPress) -> KeyPress.Result {
        guard model.openID == nil, !model.projects.isEmpty else { return .ignored }
        let mods = press.modifiers
        if mods == .command, press.characters == "f" {
            model.filterFocus += 1
            return .handled
        }
        guard mods.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        if press.key == .delete, !model.filter.isEmpty {
            model.filter.removeLast()
            return .handled
        }
        guard press.characters.count == 1, let c = press.characters.first, c.isLetter || c.isNumber else {
            return .ignored
        }
        model.filter += press.characters
        return .handled
    }
}

/// The gallery: a header with the segments, Filter and New Project (none of them until there is a project), then the cards
/// and one card to start another.
struct GalleryView: View {
    let model: ProjectsModel
    @Environment(\.coreAccent) private var paneAccent
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var hasAny: Bool { !model.projects.isEmpty || !model.archivedList.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppHeader {
                Text("Projects").coreFont(size: MacTextSize.large, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
            } actions: {
                if hasAny {
                    CoreSegmented(
                        "Show", segments: GallerySegment.allCases.map { CoreSegment($0, label($0)) },
                        selection: Binding(get: { model.segment }, set: { model.segment = $0 })
                    )
                    FilterField(
                        text: Binding(get: { model.filter }, set: { model.filter = $0 }),
                        focusRequest: model.filterFocus)
                    AppActionTile(
                        title: "New Project", symbol: "plus", key: "⌘N", hue: GlassInk.accent(paneAccent),
                        prominent: true
                    ) { model.newProject() }
                    .disabled(model.newProjectBlock != nil)
                    .help(model.newProjectBlock ?? "New Project  ⌘N")
                    .accessibilityIdentifier("projects-new")
                }
            }
            if let why = model.stale { staleNotice(why) }
            content
        }
        // The mockup's gallery: the header and the grid share one column, at most 1240 wide, centred.
        .frame(maxWidth: Self.maxWidth + Space.s4 * 2)
        .frame(maxWidth: .infinity)
        .foregroundStyle(GlassInk.primary)
        .coreFont(size: MacTextSize.body)
        // The cards rise once, when the first list is there; coming back from a space the gallery just fades in.
        .task(id: model.load) {
            guard model.load == .ready, !model.galleryRisen else { return }
            try? await Task.sleep(for: .milliseconds(40))
            model.galleryRisen = true
        }
    }

    private func label(_ s: GallerySegment) -> String {
        let n = model.count(s)
        return switch s {
        case .all: "All \(n)"
        case .running: "Running \(n)"
        case .archived: "Archived \(n)"
        }
    }

    /// The Core's words without the parenthesis tail ("(timeout)").
    static func plain(_ why: String) -> String {
        why.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
    }

    /// The list on screen is the last one the Core gave: said, with its age and a way to ask again.
    private func staleNotice(_ why: String) -> some View {
        CoreNotice(
            symbol: "wifi.exclamationmark", title: "Showing the list from \(model.listAge() ?? "a while ago").",
            text: Self.plain(why), tone: .warn
        ) {
            Button("Try again") { model.resync() }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
        }
        .padding(.horizontal, Space.s4).padding(.bottom, Space.s3)
        .accessibilityIdentifier("projects-stale")
    }

    @ViewBuilder private var content: some View {
        switch model.load {
        case .loading:
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: Space.s6) {
                    ForEach(0..<3, id: \.self) { _ in ProjectCardSkeleton() }
                }
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s6).padding(.top, Space.s2)
            }
            .scrollIndicators(.never)
        case .notConnected:
            centered(
                CoreStateCard(
                    symbol: "wifi.slash", title: "Not connected",
                    line: "Projects live on your Core. They show up here once this Mac is connected.",
                    primary: CoreAction("Connect this Mac") { model.host.shell.launcher.entry("settings")?.run() }))
        case .failed(let why):
            centered(
                CoreStateCard(
                    symbol: "exclamationmark.triangle", title: "Projects did not load", line: Self.plain(why),
                    primary: CoreAction("Try again") { model.resync() }))
        case .ready where !hasAny:
            ProjectsEmptyHero(model: model)
        case .ready:
            cards
        }
    }

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: Space.s6) {
                    ForEach(Array(model.shown.enumerated()), id: \.element.id) { i, p in
                        ProjectCard(model: model, project: p, index: i, settled: model.galleryRisen).id(p.id)
                    }
                    if model.filter.isEmpty, model.segment == .all {
                        NewProjectCard(model: model, index: model.shown.count, settled: model.galleryRisen)
                    }
                }
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s6).padding(.top, Space.s2)
                // Cards come and go with a fade as the segment or the Filter changes.
                .animation(Motion.out(Motion.ui), value: model.shown.map(\.id))
                // A list that may be old is shown a little quieter.
                .opacity(model.stale == nil ? 1 : 0.85)
                .onGeometryChange(for: Int.self) { g in
                    max(1, Int((g.size.width - Space.s4 * 2 + Space.s6) / (340 + Space.s6)))
                } action: { model.galleryColumns = $0 }
                if model.shown.isEmpty { nothingHere }
            }
            .scrollIndicators(.never)
            // The arrow keys' card scrolls into view.
            .onChange(of: model.cursor) { _, id in
                guard let id else { return }
                withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) { proxy.scrollTo(id, anchor: nil) }
            }
        }
    }

    /// Nothing to show for the segment or the Filter: the words, and what can be done about it.
    @ViewBuilder private var nothingHere: some View {
        if !model.filterText.isEmpty {
            VStack(spacing: Space.s3) {
                Text("No project matches “\(model.filterText)”.").foregroundStyle(GlassInk.secondary)
                HStack(spacing: Space.s2) {
                    Button("Clear filter") { model.filter = "" }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    Button("Create “\(model.filterText)”") { model.newProject(name: model.filterText) }
                        .buttonStyle(CoreButtonStyle(.prominent, size: .small))
                        .disabled(model.newProjectBlock != nil)
                        .help(model.newProjectBlock ?? "Start a project with this name")
                }
            }
            .frame(maxWidth: .infinity).padding(.top, Space.s2)
        } else if model.segment != .all {
            Text(model.segment == .running ? "Nothing is running right now." : "No archived projects.")
                .foregroundStyle(GlassInk.secondary).frame(maxWidth: .infinity).padding(.top, Space.s6)
        }
    }

    static let maxWidth: CGFloat = 1240
    /// Three cards to a row on a full-size pane (the mockup's grid, gap 24); fewer when the pane is narrower.
    static let columns = [GridItem(.adaptive(minimum: 340, maximum: .infinity), spacing: Space.s6, alignment: .top)]

    private func centered<V: View>(_ v: V) -> some View {
        v.frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.s4)
    }
}

/// The gallery's Filter, on the design system's field surface.
/// TODO(design-system): proposal CoreSearchField (a field with a magnifier and a clear button, no label above it).
public struct FilterField: View {
    @Binding var text: String
    let label: String
    /// Counts up to ask for focus (⌘F).
    let focusRequest: Int
    @FocusState private var focused: Bool
    public init(text: Binding<String>, label: String = "Filter projects", focusRequest: Int = 0) {
        _text = text
        self.label = label
        self.focusRequest = focusRequest
    }
    public var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass").coreFont(size: MacTextSize.body, weight: .medium)
                .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            TextField("", text: $text, prompt: Text("Filter").foregroundStyle(GlassInk.secondary))
                .textFieldStyle(.plain).focused($focused).frame(width: Space.s8 * 4)
                .accessibilityLabel(label)
            if !text.isEmpty {
                CoreIconButton(symbol: "xmark", label: "Clear the filter") { text = "" }
            }
        }
        .padding(.horizontal, Space.s3).frame(height: MacSize.controlLg)
        .coreFieldSurface(focused: focused)
        .onChange(of: focusRequest) { focused = true }
        .onExitCommand { if text.isEmpty { focused = false } else { text = "" } }
    }
}
