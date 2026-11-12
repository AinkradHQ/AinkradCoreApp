import CoreUI
import SwiftUI

/// The widget gallery (home-clocks, "Widget gallery"): a framed dialog over the dimmed Home, every widget as a card with a
/// live preview, its name and what it shows, a size choice and Add. A widget already on Home says so, and its size choice
/// resizes it in place. Add puts it in the first free spot; dragging a preview onto Home drops it where you let go.
struct WidgetGallery: View {
    @Bindable var shell: ShellModel
    let begin: (WidgetKind, WidgetSize, CGPoint) -> Void
    let move: (CGPoint) -> Void
    let end: (Bool) -> Void

    /// The clocks first, as the mockup; then the Core widgets.
    static let order: [WidgetKind] = [
        .digital, .clock, .today, .machines, .spend, .quick, .running, .needs, .events, .core, .board,
    ]
    private var kinds: [WidgetKind] { Self.order.filter { $0 != .board || WidgetKind.boardShown } }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.s4, alignment: .top), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text("Widgets").coreFont(size: MacTextSize.large, weight: .semibold).accessibilityAddTraits(.isHeader)
                Text("Add one clock, the other, or both.").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
                Spacer(minLength: Space.s3)
                CoreIconButton(symbol: "xmark", label: "Close") { shell.addingWidget = false }
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: Space.s4) {
                    ForEach(kinds) { kind in
                        GalleryCard(kind: kind, shell: shell, begin: begin, move: move, end: end)
                    }
                }
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: Space.s8 * 17)
            HStack(spacing: Space.s3) {
                Text("Drag a widget from here onto Home, or press Add and it lands in the first free spot.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                Spacer(minLength: Space.s3)
                Button("Done") { shell.addingWidget = false }.buttonStyle(CoreButtonStyle(.secondary))
            }
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s6)
        .frame(width: Space.s8 * 27.5)
        .coreFrame(radius: Radius.panel)
        .coreModalEntrance()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Widgets")
    }
}

/// One widget in the gallery: a plain well (the gallery's frame is the one glass surface). Hover lifts the fill and draws
/// the blue edge, the "picked" card of the mockup.
private struct GalleryCard: View {
    let kind: WidgetKind
    @Bindable var shell: ShellModel
    let begin: (WidgetKind, WidgetSize, CGPoint) -> Void
    let move: (CGPoint) -> Void
    let end: (Bool) -> Void
    @State private var chosen: WidgetSize?
    @State private var hovering = false
    @State private var dragging = false

    /// The copy the size choice and Remove act on: only when exactly one is on Home.
    private var placed: WidgetItem? { shell.widgets.onlyCopy(of: kind) }
    private var onHome: Bool { shell.widgets.items.contains { $0.kind == kind } }
    private var size: WidgetSize { placed?.size ?? chosen ?? kind.sizes[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            preview
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s2) {
                    Text(kind.title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                    Spacer(minLength: Space.s2)
                    if onHome {
                        Label("On Home", systemImage: "checkmark").labelStyle(OnHomeLabel())
                            .transition(.opacity)
                    }
                }
                Text(kind.about).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: Space.s8, alignment: .topLeading)
            }
            HStack(spacing: Space.s2) {
                if kind.sizes.count > 1 {
                    CoreSegmented(
                        "Size", segments: kind.sizes.map { CoreSegment($0, $0.short) },
                        selection: Binding(get: { size }, set: pick)
                    )
                    .help(kind.sizes.map(\.title).joined(separator: ", "))
                }
                Spacer(minLength: 0)
                if let placed {
                    Button("Remove") { shell.removeWidget(placed.id) }
                        .buttonStyle(CoreButtonStyle(.plain, size: .small))
                        .accessibilityLabel("Remove \(kind.title)")
                } else {
                    Button("Add") { shell.addWidget(kind, size) }
                        .buttonStyle(CoreButtonStyle(.prominent, size: .small))
                        .accessibilityLabel("Add \(kind.title), \(size.spoken)")
                }
            }
        }
        .padding(Space.s3)
        .coreWell(radius: Radius.row, active: hovering)
        .overlay {
            coreShape(Radius.row).strokeBorder(GlassInk.blue.opacity(hovering ? 1 : 0), lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .animation(Motion.out(Motion.hover), value: placed?.id)
        .animation(Motion.out(Motion.hover), value: onHome)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(kind.title)
    }

    /// On Home the choice resizes the widget there; otherwise it is the size Add will use.
    private func pick(_ s: WidgetSize) {
        if let placed { shell.resizeWidget(placed.id, to: s) } else { chosen = s }
    }

    /// The widget itself at the chosen size, scaled down into a plain well. Drag it onto Home to place it.
    private var preview: some View {
        let full = DeskGrid.frameSize(size)
        let k = min(226 / full.width, 116 / full.height, 0.72)
        return WidgetBody(kind: kind, size: size, shell: shell)
            .padding(Space.s4).frame(width: full.width, height: full.height, alignment: .topLeading)
            .coreWell(radius: Radius.pane)
            .scaleEffect(k)
            .frame(width: full.width * k, height: full.height * k)
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity).frame(height: Space.s8 * 4 + Space.s1)
            .background(GlassInk.well, in: coreShape(Radius.control))
            .clipShape(coreShape(Radius.control))
            .contentShape(coreShape(Radius.control))
            .help("Drag onto Home")
            .highPriorityGesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named(HomeView.stageSpace))
                    .onChanged { v in
                        if v.translation == .zero { return }
                        // The first change starts the drag; the held widget starts at the pointer's start point.
                        if !dragging {
                            dragging = true
                            begin(kind, size, v.startLocation)
                        }
                        move(v.location)
                    }
                    .onEnded { _ in
                        dragging = false
                        end(false)
                    }
            )
            .accessibilityHidden(true)
    }
}

/// "✓ On Home": a blue check and quiet words.
private struct OnHomeLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.s1) {
            configuration.icon.foregroundStyle(GlassInk.blueInk)
            configuration.title.foregroundStyle(GlassInk.secondary)
        }
        .coreFont(size: MacTextSize.meta, weight: .medium)
    }
}
