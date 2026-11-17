import CoreUI
import Shell
import SwiftUI

/// The Projects pane: the gallery, or the open project's space. Opening and going back cross-fade (Reduce Motion or not:
/// the two screens share no element that could travel).
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
        .paneLook(nil)
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
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
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

/// The gallery: a header with Filter and New Project, then the cards over the pane's surface and one card to start another.
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
                AppActionTile(title: "New Project", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                    model.newProject()
                }
                .disabled(model.readOnly || model.load == .notConnected)
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

    static let columns = [GridItem(.adaptive(minimum: 280, maximum: 480), spacing: Space.s4, alignment: .top)]

    private func centered<V: View>(_ v: V) -> some View {
        v.frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.s4)
    }
}

/// The gallery's Filter: a quiet well with a magnifier, never a pill.
private struct FilterField: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass").coreFont(size: MacTextSize.body, weight: .medium)
                .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            TextField("", text: $text, prompt: Text("Filter").foregroundStyle(GlassInk.secondary))
                .textFieldStyle(.plain).focused($focused).frame(width: Space.s8 * 3)
                .accessibilityLabel("Filter projects")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark").coreFont(size: 9, weight: .bold).foregroundStyle(GlassInk.secondary)
                }
                .buttonStyle(.plain).help("Clear the filter").accessibilityLabel("Clear the filter")
            }
        }
        .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd + 4)
        .coreFieldSurface(focused: focused)
        .onExitCommand { if text.isEmpty { focused = false } else { text = "" } }
    }
}
