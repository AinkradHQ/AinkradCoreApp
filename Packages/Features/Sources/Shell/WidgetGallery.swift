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
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Self.cats, id: \.self) { cat in
                        let kinds = WidgetKind.allCases.filter { $0.category == cat }
                        if !kinds.isEmpty {
                            Text(cat).font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(
                                palette.text2
                            )
                            .padding(.horizontal, 6).padding(.top, 8)
                            ForEach(kinds) { kind in card(kind) }
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 14)
            }
        }
        .corePanel(radius: 20, padding: 0)
        .overlay { coreShape(20).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add a widget")
    }

    private func size(_ k: WidgetKind) -> WidgetSize { sel[k] ?? k.sizes[min(1, k.sizes.count - 1)] }

    private func card(_ kind: WidgetKind) -> some View {
        let s = size(kind)
        return VStack(alignment: .leading, spacing: 8) {
            preview(kind, s)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(.system(size: MacTextSize.body, weight: .semibold))
                Text(kind.about).font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 4) {
                ForEach(kind.sizes, id: \.self) { z in
                    Button(z.title) { sel[kind] = z }
                        .buttonStyle(ChoiceStyle(on: z == s))
                        .accessibilityAddTraits(z == s ? .isSelected : [])
                }
                Spacer(minLength: 0)
                Button("Add") { shell.addWidget(kind, s) }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .accessibilityLabel("Add \(kind.title), \(s.title)")
            }
        }
        .padding(10)
        .background(palette.glassCard, in: coreShape(14))
        .overlay { coreShape(14).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }

    private func preview(_ kind: WidgetKind, _ s: WidgetSize) -> some View {
        let full = DeskGrid.frameSize(s)
        let k = min(268 / full.width, 150 / full.height, 0.6)
        return ZStack {
            WidgetBody(kind: kind, size: s, shell: shell)
                .padding(14).frame(width: full.width, height: full.height, alignment: .topLeading)
                .background(palette.glassCard, in: coreShape(20))
                .overlay { coreShape(20).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
                .scaleEffect(k)
                .frame(width: full.width * k, height: full.height * k)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity).frame(height: 168)
        .background(palette.text.opacity(0.05), in: coreShape(10))
        .clipShape(coreShape(10))
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

/// The size choice in the gallery (`.wd-gs .btn.on`): blue tint and edge when chosen.
private struct ChoiceStyle: ButtonStyle {
    let on: Bool
    @Environment(\.corePalette) private var palette
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: MacTextSize.meta, weight: .medium))
            .foregroundStyle(on ? palette.primary : palette.text)
            .padding(.horizontal, Space.s2).frame(minHeight: MacSize.controlSm)
            .background(on ? palette.navActive : hovering ? palette.uDim : .clear, in: coreShape(Radius.chip))
            .overlay {
                coreShape(Radius.chip).strokeBorder(on ? palette.navActiveEdge : palette.glassCardEdge, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Motion.out(Motion.hover), value: hovering)
    }
}
