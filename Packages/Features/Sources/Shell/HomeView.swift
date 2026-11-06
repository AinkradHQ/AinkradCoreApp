import CoreUI
import SwiftUI

/// What a widget drag holds: the widget, where the pointer grabbed it, and the layout it would make if dropped now.
struct DeskDrag {
    var item: WidgetItem
    var isNew: Bool
    var grab: CGSize
    var point: CGPoint
    var cell: [Int]?
    var preview: [WidgetItem]?
    var origin: CGPoint { CGPoint(x: point.x - grab.width, y: point.y - grab.height) }
}

/// Home: the sky and the widget desk (`widgets.js`): an 8 x 5 snap grid on the prototype's 1440 x 900 stage, direct-manipulation
/// drag, a gallery, edit mode, Undo, persistence. The greeting sits between the columns.
struct HomeView: View {
    @Bindable var shell: ShellModel
    @State private var drag: DeskDrag?
    @State private var arrived = false
    @FocusState private var focus: UUID?
    @Environment(\.corePalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce

    static let stageSpace = "stage"
    static let galleryLeft = ShellMetrics.designSize.width - 12 - 340

    var body: some View {
        GeometryReader { geo in
            let design = ShellMetrics.designSize
            let u = min(geo.size.width / design.width, geo.size.height / design.height)
            stage
                .frame(width: design.width, height: design.height, alignment: .topLeading)
                .scaleEffect(u, anchor: .topLeading)
                .frame(width: design.width * u, height: design.height * u, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { arrived = true }
    }

    private var stage: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .contextMenu {
                    Button("Add Widget…") { shell.addingWidget = true }
                    Button(shell.editingWidgets ? "Done Editing" : "Edit Widgets") { shell.editingWidgets.toggle() }
                    Divider()
                    Button("Reset Layout") { shell.resetWidgets() }
                }
            GreetingView(profile: shell.profile).frame(maxWidth: .infinity).padding(.top, Self.greetingTop)
                .allowsHitTesting(true)
            ghost
            ForEach(sorted) { item in card(item) }
            // Hidden at rest: Add Widget and Edit Widgets live in the right-click menu on the sky. The bar shows only
            // while editing or adding, so there is a Done to press.
            if shell.editingWidgets || shell.addingWidget {
                controls.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, Space.s2)
                    .transition(.opacity.combined(with: .offset(y: coreMove(reduce, 12))))
            }
            if shell.addingWidget {
                WidgetGallery(shell: shell, begin: beginFromGallery, move: moveDrag, end: endDrag)
                    .frame(width: 340).frame(maxHeight: .infinity)
                    .padding(.top, 46).padding(.bottom, 12).padding(.trailing, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity.combined(with: .offset(x: coreMove(reduce, 24))))
            }
        }
        .coordinateSpace(name: Self.stageSpace)
        .animation(reduce ? .easeOut(duration: 0.2) : Motion.out(Motion.ui), value: shell.addingWidget)
    }

    /// The prototype puts the greeting in the upper third (about 24% of the height).
    private static let greetingTop = ShellMetrics.designSize.height * 0.24

    // MARK: layout

    /// Where each widget is drawn: the live layout, or the preview while one is held.
    private var shown: [WidgetItem] {
        var base = drag?.preview ?? shell.widgets.items
        if let d = drag, d.isNew, !base.contains(where: { $0.id == d.item.id }) { base.append(d.item) }
        return base
    }
    private var sorted: [WidgetItem] {
        shown.sorted { ($0.y, $0.x, $0.id.uuidString) < ($1.y, $1.x, $1.id.uuidString) }
    }

    @ViewBuilder private func card(_ item: WidgetItem) -> some View {
        let held = drag?.item.id == item.id
        let p = held ? drag!.origin : DeskGrid.origin(item.x, item.y)
        let index = sorted.firstIndex { $0.id == item.id } ?? 0
        DeskWidget(item: item, shell: shell, editing: shell.editingWidgets, lifting: held, focus: $focus)
            .rise(arrived, index + 1, reduce)
            .offset(x: p.x, y: p.y)
            .animation(held || reduce ? nil : Motion.out(Motion.move), value: item)
            .zIndex(held ? 30 : 0)
            .simultaneousGesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named(Self.stageSpace))
                    .onChanged { v in
                        if drag == nil {
                            let o = DeskGrid.origin(item.x, item.y)
                            beginDrag(
                                item, isNew: false,
                                grab: CGSize(width: v.startLocation.x - o.x, height: v.startLocation.y - o.y),
                                at: v.location)
                        }
                        moveDrag(v.location)
                    }
                    .onEnded { _ in endDrag(cancel: false) }
            )
            .transition(.opacity.combined(with: .scale(scale: reduce ? 1 : 0.9)))
    }

    @ViewBuilder private var ghost: some View {
        if let d = drag, let c = d.cell, d.preview != nil {
            let o = DeskGrid.origin(c[0], c[1])
            let s = DeskGrid.frameSize(d.item.size)
            coreShape(20).fill(palette.glassCard).overlay {
                coreShape(20).strokeBorder(palette.navActiveEdge, lineWidth: 1.5)
            }
            .frame(width: s.width, height: s.height).offset(x: o.x, y: o.y).allowsHitTesting(false)
            .animation(reduce ? nil : Motion.out(0.18), value: c)
            .accessibilityHidden(true)
        }
    }

    // MARK: drag

    private func beginDrag(_ item: WidgetItem, isNew: Bool, grab: CGSize, at p: CGPoint) {
        drag = DeskDrag(item: item, isNew: isNew, grab: grab, point: p)
    }

    private func beginFromGallery(_ kind: WidgetKind, _ size: WidgetSize, _ p: CGPoint) {
        let item = WidgetItem(kind: kind, size: size, x: 0, y: 0)
        beginDrag(item, isNew: true, grab: CGSize(width: DeskGrid.frameSize(size).width / 2, height: 24), at: p)
    }

    private func moveDrag(_ p: CGPoint) {
        guard var d = drag else { return }
        d.point = p
        let over = !d.isNew || !shell.addingWidget || d.origin.x + d.grab.width < Self.galleryLeft
        if over {
            let c = DeskGrid.cell(at: d.origin, size: d.item.size)
            if d.cell != [c.x, c.y] {
                d.cell = [c.x, c.y]
                let list = d.isNew ? shell.widgets.items + [d.item] : shell.widgets.items
                d.preview = WidgetLayout.moving(d.item, to: c.x, c.y, in: list)
                if d.preview == nil { d.cell = nil }
            }
        } else {
            d.cell = nil
            d.preview = nil
        }
        drag = d
    }

    private func endDrag(cancel: Bool) {
        guard let d = drag else { return }
        if !cancel, let next = d.preview, d.cell != nil {
            drag = nil
            shell.setWidgets(next)
            if d.isNew { shell.showToast("Added \(d.item.kind.title)") }
        } else {
            drag = nil
        }
    }

    // MARK: greeting and controls

    private var controls: some View {
        HStack(spacing: Space.s1) {
            Button {
                shell.addingWidget.toggle()
            } label: {
                Label("Add Widget", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            Button {
                shell.editingWidgets.toggle()
            } label: {
                Label(shell.editingWidgets ? "Done" : "Edit Widgets", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(CoreButtonStyle(shell.editingWidgets ? .prominent : .secondary, size: .small))
        }
        // The two buttons are glass themselves; no second glass behind them.
    }
}

/// "Good morning, Ahmed" and the launcher hint. Without a name it offers to take one (the name is kept on this Mac only).
struct GreetingView: View {
    @Bindable var profile: UserProfile
    @State private var asking = false
    @State private var draft = ""
    @State private var shown = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette

    /// White on both skies: the day sky is a mid blue, where navy text sinks (Ahmed, 2026-11-05). A deep-blue shadow keeps it
    /// readable over the bright clouds.
    private var ink: Color { .white }
    private var dayPart: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    var body: some View {
        VStack(spacing: Space.s2) {
            Text(profile.hasName ? "\(dayPart), \(profile.name)" : dayPart)
                .font(.system(size: 28, weight: .semibold))
            HStack(spacing: Space.s2) {
                Text("Press")
                CoreKeycap("⌘K")
                Text("to open the launcher.")
            }
            .font(.system(size: 14)).opacity(0.85)
            if !profile.hasName { nameAsk }
        }
        .foregroundStyle(ink)
        .shadow(
            color: Color(red: 0, green: 0.05, blue: 0.18).opacity(scheme == .dark ? 0.65 : 0.45),
            radius: 12, y: 1
        )
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : coreMove(reduce, 10))
        .animation(reduce ? .easeOut(duration: 0.3) : Motion.out(1.0), value: shown)
        .onAppear { shown = true }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var nameAsk: some View {
        if asking {
            HStack(spacing: Space.s2) {
                CoreTextField("Your name", placeholder: "Ahmed", text: $draft, autofocus: true, onSubmit: save)
                    .frame(width: 200)
                Button("Save") { save() }.buttonStyle(CoreButtonStyle(.prominent, size: .small))
                    .disabled(UserProfile.clean(draft).isEmpty)
            }
        } else {
            Button("Add your name") { asking = true }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
        }
    }

    private func save() {
        profile.set(draft)
        asking = false
    }
}
