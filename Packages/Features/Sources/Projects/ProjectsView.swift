import CoreUI
import Shell
import SwiftUI

/// The Projects pane: the gallery, or the open project's space. Opening and going back cross-fade: the two screens share no
/// element that could travel. The pane draws no background of its own (`own: true`), so the cards sit over the wallpaper.
struct ProjectsView: View {
    let model: ProjectsModel
    @FocusState private var paneFocus: Bool

    var body: some View {
        ZStack {
            if let project = model.open {
                ProjectSpaceView(model: model, project: project).transition(.opacity)
            } else {
                GalleryView(model: model).transition(.opacity)
            }
        }
        .appLook(AppLookPrefs.shared("projects"))
        .clipShape(coreShape(Radius.cardMac))
        .focusable()
        .focused($paneFocus)
        .focusEffectDisabled()
        .onAppear { paneFocus = true }
        .retakeFocus(after: model.host.shell, pane: "projects") { paneFocus = true }
        .onKeyPress(.escape) {
            if model.quickOpen {
                model.quickOpen = false
                return .handled
            }
            if model.openID != nil {
                model.closeProject()
                return .handled
            }
            return .ignored
        }
        .coreSideKeys { move($0) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.return) {
            guard model.openID == nil, !model.quickOpen, let id = model.cursor else { return .ignored }
            model.openProject(id)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projects-pane")
    }

    /// Arrow keys step the cursor through the gallery's cards in reading order.
    private func move(_ step: Int) -> KeyPress.Result {
        guard model.openID == nil, !model.quickOpen else { return .ignored }
        let ids = model.shown.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let at = model.cursor.flatMap { ids.firstIndex(of: $0) }
        let next = at.map { min(max($0 + step, 0), ids.count - 1) } ?? (step > 0 ? 0 : ids.count - 1)
        model.cursor = ids[next]
        return .handled
    }
}

/// The gallery: a header with Filter and New Project, then the cards and one card to start another.
struct GalleryView: View {
    let model: ProjectsModel
    @State private var settled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppHeader {
                Text("Projects").coreFont(size: MacTextSize.large, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
            } actions: {
                FilterField(text: Binding(get: { model.filter }, set: { model.filter = $0 }))
                Button {
                    model.newProject()
                } label: {
                    Label("New Project", systemImage: "plus")
                }
                .buttonStyle(CoreButtonStyle(.prominent))
                .disabled(model.readOnly || model.load == .notConnected)
                .help("New Project  ⌘N")
                .accessibilityIdentifier("projects-new")
            }
            content
        }
        .foregroundStyle(GlassInk.primary)
        .coreFont(size: MacTextSize.body)
        .overlay(alignment: .topTrailing) { quick }
        .onAppear { settled = true }
        .animation(Motion.out(Motion.ui), value: model.quickOpen)
    }

    @ViewBuilder private var quick: some View {
        if model.quickOpen {
            ZStack(alignment: .topTrailing) {
                // A click anywhere else closes it, like any pop-over.
                Color.clear.contentShape(Rectangle()).onTapGesture { model.quickOpen = false }
                QuickNewProject(model: model)
                    .padding(.trailing, Space.s4).padding(.top, Space.s8 + Space.s5)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.load {
        case .loading:
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: Space.s4) {
                    ForEach(0..<3, id: \.self) { _ in ProjectCardSkeleton() }
                }
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
            }
            .scrollIndicators(.never)
        case .notConnected:
            centered(
                CoreStateCard(
                    symbol: "wifi.slash", title: "Not connected",
                    line: "Projects live on your Core. They show up here once this Mac is connected."))
        case .failed(let why):
            centered(
                CoreStateCard(
                    symbol: "exclamationmark.triangle", title: "Projects did not load", line: why,
                    primary: CoreAction("Try again") { model.resync() }))
        case .ready:
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: Space.s4) {
                    ForEach(Array(model.shown.enumerated()), id: \.element.id) { i, p in
                        ProjectCard(model: model, project: p, index: i, settled: settled)
                    }
                    if model.filter.isEmpty || model.shown.isEmpty {
                        NewProjectCard(model: model, index: model.shown.count, settled: settled)
                    }
                }
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
                if !model.filter.isEmpty, model.shown.isEmpty {
                    Text("No project matches “\(model.filter)”.").foregroundStyle(GlassInk.secondary)
                        .frame(maxWidth: .infinity).padding(.top, Space.s2)
                }
            }
            .scrollIndicators(.never)
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

/// The gallery's Filter, on the design system's field surface.
/// TODO(design-system): proposal CoreSearchField (a field with a magnifier and a clear button, no label above it).
public struct FilterField: View {
    @Binding var text: String
    let label: String
    @FocusState private var focused: Bool
    public init(text: Binding<String>, label: String = "Filter projects") {
        _text = text
        self.label = label
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
        .onExitCommand { if text.isEmpty { focused = false } else { text = "" } }
    }
}
