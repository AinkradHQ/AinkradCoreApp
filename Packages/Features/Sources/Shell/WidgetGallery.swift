import CoreUI
import SwiftUI

/// The Add Widget panel (`widgets.js gallery()`): every widget with a live preview at the chosen size, by category. Add puts it in
/// the first free cell; dragging the preview onto Home drops it where you let go.
struct WidgetGallery: View {
    @Bindable var shell: ShellModel
    let begin: (WidgetKind, WidgetSize, CGPoint) -> Void
    let move: (CGPoint) -> Void
    let end: (Bool) -> Void
    @State private var sel: [WidgetKind: WidgetSize] = [:]
    @Environment(\.corePalette) private var palette

    private static let cats = ["Core", "Work", "Utilities"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Widget").font(.system(size: MacTextSize.title, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { shell.addingWidget = false }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
            .padding(.horizontal, Space.s4).padding(.top, Space.s3).padding(.bottom, Space.s2)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(Self.cats, id: \.self) { cat in
                        let kinds = WidgetKind.allCases.filter { $0.category == cat }
                        if !kinds.isEmpty {
                            Text(cat).font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(
                                palette.text2
                            )
                            .padding(.horizontal, Space.s2).padding(.top, Space.s2)
                            ForEach(kinds) { kind in card(kind) }
                        }
                    }
                }
                .padding(.horizontal, Space.s3).padding(.bottom, Space.s3)
            }
        }
        .corePanel(radius: Radius.panel, padding: 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add a widget")
    }

    private func size(_ k: WidgetKind) -> WidgetSize { sel[k] ?? k.sizes[min(1, k.sizes.count - 1)] }

    private func card(_ kind: WidgetKind) -> some View {
        let s = size(kind)
        return VStack(alignment: .leading, spacing: Space.s2) {
            preview(kind, s)
            VStack(alignment: .leading, spacing: 0) {
                Text(kind.title).font(.system(size: MacTextSize.body, weight: .semibold))
                Text(kind.about).font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CoreSegmented(
                "Size", segments: kind.sizes.map { CoreSegment($0, $0.title) },
                selection: Binding(get: { size(kind) }, set: { sel[kind] = $0 }), fill: true)
            HStack(spacing: Space.s2) {
                Spacer(minLength: 0)
                Button("Add") { shell.addWidget(kind, s) }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .accessibilityLabel("Add \(kind.title), \(s.title)")
            }
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreFrame(radius: Radius.cardMac + Space.s1, rim: Space.s1)
        .accessibilityElement(children: .contain)
    }

    private func preview(_ kind: WidgetKind, _ s: WidgetSize) -> some View {
        let full = DeskGrid.frameSize(s)
        let k = min(Space.s8 * 8 / full.width, Space.s8 * 4 / full.height, 0.6)
        return ZStack {
            WidgetBody(kind: kind, size: s, shell: shell)
                .padding(Space.s3).frame(width: full.width, height: full.height, alignment: .topLeading)
                .background(GlassInk.well, in: coreShape(Radius.panel))
                .scaleEffect(k)
                .frame(width: full.width * k, height: full.height * k)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity).frame(height: Space.s8 * 5)
        .background(GlassInk.well, in: coreShape(Radius.control))
        .clipShape(coreShape(Radius.control))
        .contentShape(Rectangle())
        .help("Drag onto Home")
        .highPriorityGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .named(HomeView.stageSpace))
                .onChanged { v in
                    if v.translation == .zero { return }
                    // The first change starts the drag; the held widget starts at the pointer's start point.
                    if !started {
                        started = true
                        begin(kind, s, v.startLocation)
                    }
                    move(v.location)
                }
                .onEnded { _ in
                    started = false
                    end(false)
                }
        )
        .accessibilityHidden(true)
    }

    @State private var started = false
}
