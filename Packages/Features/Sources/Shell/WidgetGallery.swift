import CoreUI
import SwiftUI

/// The widget gallery (05-home mockup, "gallery"): a framed dialog over the dimmed Home. The kinds are listed on the left
/// by category; the right shows the chosen kind in all four sizes (Large, Wide, Medium, Small) and its Add button. Pick a
/// size by clicking it. A widget already on Home says so, and its size choice resizes it in place. Add puts it in the
/// first free spot; dragging a preview onto Home drops it where you let go.
struct WidgetGallery: View {
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var shell: ShellModel
    let begin: (WidgetKind, WidgetSize, CGPoint) -> Void
    let move: (CGPoint) -> Void
    let end: (Bool) -> Void

    /// The mockup's order inside each category.
    static let order: [WidgetKind] = [
        .digital, .clock, .quick, .today, .needs, .approvals, .running, .spend, .aiusage, .machines, .board, .events,
        .core, .terminals, .projects, .brain, .todaynote, .weather, .calendar,
    ]
    private var kinds: [WidgetKind] { Self.order.filter { $0 != .board || WidgetKind.boardShown } }
    private static let categories = ["Core", "Work", "Utilities"]

    @State private var current: WidgetKind = .terminals
    @State private var chosen: WidgetSize = .m
    @State private var dragging = false

    /// The copy the size choice and Remove act on: only when exactly one is on Home.
    private var placed: WidgetItem? { shell.widgets.onlyCopy(of: current) }
    private var size: WidgetSize { placed?.size ?? chosen }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .foregroundStyle(GlassInk.primary)
        .frame(width: Space.s8 * 28, height: Space.s8 * 19)
        .coreFrame(radius: Radius.pane)
        .coreModalEntrance()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Widgets")
        .onAppear { chosen = current.sizes[0] }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach(Self.categories, id: \.self) { cat in
                    Text(cat).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
                        .padding(.horizontal, Space.s3).padding(.top, Space.s3)
                    ForEach(kinds.filter { $0.category == cat }) { k in row(k) }
                }
            }
            .padding(Space.s3)
        }
        .frame(width: Space.s8 * 7)
        .background(GlassInk.well)
    }

    private func row(_ k: WidgetKind) -> some View {
        let on = k == current
        return Button {
            current = k
            chosen = shell.widgets.onlyCopy(of: k)?.size ?? k.sizes[0]
        } label: {
            HStack(spacing: Space.s2) {
                IconTile(k.symbol, hue: GlassInk.accent(paneAccent), size: 24)
                Text(k.title).coreFont(size: MacTextSize.body, weight: on ? .semibold : .regular).lineLimit(1)
                Spacer(minLength: 0)
                if k.isNew { Text("New").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.blueInk) }
                if shell.widgets.items.contains(where: { $0.kind == k }) {
                    Image(systemName: "checkmark").foregroundStyle(GlassInk.secondary).accessibilityLabel("On Home")
                }
            }
            .padding(.horizontal, Space.s2).frame(minHeight: 32)
            .background(on ? GlassInk.wellEdge : .clear, in: coreShape(Radius.control))
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .top, spacing: Space.s3) {
                IconTile(current.symbol, hue: GlassInk.accent(paneAccent), size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.title).coreFont(size: MacTextSize.large, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)
                    Text(current.about).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: Space.s3)
                CoreIconButton(symbol: "xmark", label: "Close") { shell.addingWidget = false }
            }
            previews
            legend
            Spacer(minLength: 0)
            HStack(spacing: Space.s3) {
                Text("Drag a widget onto Home, or press Add and it lands in the first free spot.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                Spacer(minLength: Space.s3)
                Button("Done") { shell.addingWidget = false }.buttonStyle(CoreButtonStyle(.secondary))
                if let placed {
                    Button("Remove \(current.title)") { shell.removeWidget(placed.id) }
                        .buttonStyle(CoreButtonStyle(.secondary))
                } else {
                    Button("Add \(current.title) · \(size.title)") { shell.addWidget(current, size) }
                        .buttonStyle(CoreButtonStyle(.prominent))
                }
            }
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Large on the left; Wide over Medium and Small on the right, as the mockup.
    private var previews: some View {
        let k: CGFloat = 0.62
        return HStack(alignment: .top, spacing: Space.s4) {
            preview(.l, k)
            VStack(alignment: .leading, spacing: Space.s4) {
                preview(.w, k)
                HStack(alignment: .top, spacing: Space.s4) {
                    preview(.m, k)
                    preview(.s, k)
                }
            }
        }
        .animation(Motion.out(Motion.hover), value: current)
        .id(current)
        .transition(.opacity)
    }

    private var legend: some View {
        let words: [(WidgetSize, String)] = [
            (.s, "One number, one glance."), (.m, "The last few things."), (.w, "A chart or a row of cards."),
            (.l, "The whole story."),
        ]
        return HStack(alignment: .top, spacing: Space.s4) {
            ForEach(words, id: \.0) { s, text in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.spoken).coreFont(size: MacTextSize.meta, weight: .semibold)
                    Text(text).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// One size of the widget, scaled into a plain well. Click to choose it, drag to place it on Home.
    private func preview(_ s: WidgetSize, _ k: CGFloat) -> some View {
        let full = DeskGrid.frameSize(s)
        let on = s == size
        return WidgetBody(kind: current, size: s, shell: shell)
            .environment(\.widgetPreview, true)
            .padding(Space.s4).frame(width: full.width, height: full.height, alignment: .topLeading)
            .coreWell(radius: Radius.pane, active: on)
            .allowsHitTesting(false)
            .scaleEffect(k, anchor: .topLeading)
            .frame(width: full.width * k, height: full.height * k, alignment: .topLeading)
            .contentShape(coreShape(Radius.pane))
            .onTapGesture {
                if let placed { shell.resizeWidget(placed.id, to: s) } else { chosen = s }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named(HomeView.stageSpace))
                    .onChanged { v in
                        if v.translation == .zero { return }
                        if !dragging {
                            dragging = true
                            begin(current, s, v.startLocation)
                        }
                        move(v.location)
                    }
                    .onEnded { _ in
                        dragging = false
                        end(false)
                    }
            )
            .help("Click to choose \(s.title), drag onto Home")
            .accessibilityElement()
            .accessibilityLabel("\(current.title), \(s.spoken)")
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
