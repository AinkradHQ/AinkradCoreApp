import CoreUI
import SwiftUI

/// One widget on the desk: the glass surface (`widgets.css .wd-w`), its content, and the edit chrome (size choices, remove).
/// Hover only changes state; nothing follows the pointer.
struct DeskWidget: View {
    let item: WidgetItem
    @Bindable var shell: ShellModel
    let editing: Bool
    let lifting: Bool
    var focus: FocusState<UUID?>.Binding
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var hovering = false

    /// Apple widget corners: large and soft.
    private var radius: CGFloat { Radius.panel + Space.s1 }

    var body: some View {
        let size = DeskGrid.frameSize(item.size)
        ZStack(alignment: .topLeading) {
            WidgetBody(kind: item.kind, size: item.size, shell: shell)
                // White ink on clear glass: a soft shadow keeps it readable over bright clouds (stronger by day).
                .shadow(color: .black.opacity(palette.isDay ? 0.35 : 0.25), radius: 3, y: 1)
                .padding(Space.s4).padding(.top, editing ? Space.s8 : 0)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .opacity(editing ? 0.5 : 1)
                .allowsHitTesting(!editing)
                .animation(Motion.out(Motion.ui), value: editing)
            chrome
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(coreShape(radius))
        // Apple's Liquid Glass draws its own edge and light; no extra stroke or ring on top.
        .coreGlass(radius: radius, interactive: false, tinted: false)
        .overlay {
            coreShape(radius).fill(Color.white.opacity(hovering && !lifting ? 0.04 : 0)).allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(lifting ? 0.35 : 0.12), radius: lifting ? 30 : 14, y: lifting ? 14 : 4)
        .scaleEffect(lifting && !reduce ? 1.025 : 1)
        .animation(Motion.out(Motion.ui), value: lifting)
        .animation(Motion.out(Motion.ui), value: hovering)
        .contentShape(coreShape(radius))
        .onHover { hovering = $0 }
        .focusable()
        .focused(focus, equals: item.id)
        .focusEffectDisabled()
        .onKeyPress { press in key(press) }
        .onTapGesture { if !editing { open() } }
        .contextMenu { menu }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.kind.title) widget, \(item.size.title)")
        .accessibilityAction(named: "Remove") { shell.removeWidget(item.id) }
        .accessibilityAction(named: "Move left") { shell.moveWidget(item.id, dx: -1, dy: 0) }
        .accessibilityAction(named: "Move right") { shell.moveWidget(item.id, dx: 1, dy: 0) }
        .accessibilityAction(named: "Move up") { shell.moveWidget(item.id, dx: 0, dy: -1) }
        .accessibilityAction(named: "Move down") { shell.moveWidget(item.id, dx: 0, dy: 1) }
    }

    private func open() {
        if let id = item.kind.launch { shell.launcher.entry(id)?.run() }
    }

    private func key(_ p: KeyPress) -> KeyPress.Result {
        guard p.modifiers.isEmpty else { return .ignored }
        // Moving and removing answer the keys only while editing the desk; at rest they must not touch a widget.
        switch p.key {
        case .leftArrow where editing: shell.moveWidget(item.id, dx: -1, dy: 0)
        case .rightArrow where editing: shell.moveWidget(item.id, dx: 1, dy: 0)
        case .upArrow where editing: shell.moveWidget(item.id, dx: 0, dy: -1)
        case .downArrow where editing: shell.moveWidget(item.id, dx: 0, dy: 1)
        case .delete where editing, .deleteForward where editing: shell.removeWidget(item.id)
        case .return where !editing: open()
        default: return .ignored
        }
        return .handled
    }

    @ViewBuilder private var menu: some View {
        Button("Open") { open() }.disabled(item.kind.launch == nil)
        Menu("Size") {
            ForEach(item.kind.sizes, id: \.self) { s in
                Button {
                    shell.resizeWidget(item.id, to: s)
                } label: {
                    Text("\(s.title) · \(s.cols)×\(s.rows)")
                    if s == item.size { Image(systemName: "checkmark") }
                }
            }
        }
        Button(editing ? "Done Editing" : "Edit Widgets") { shell.editingWidgets.toggle() }
        Button("Add Widget…") { shell.addingWidget = true }
        Button("Remove", role: .destructive) { shell.removeWidget(item.id) }
    }

    /// `.wd-edit`: the size choices at the top left, remove at the top right. They fade in; they are Tab stops only while editing.
    private var chrome: some View {
        HStack {
            HStack(spacing: Space.s1) {
                ForEach(item.kind.sizes, id: \.self) { s in
                    Button {
                        shell.resizeWidget(item.id, to: s)
                    } label: {
                        sizeMark(s)
                    }
                    .buttonStyle(SizeChoiceStyle(selected: s == item.size))
                    .accessibilityLabel("\(s.title), \(s.cols) by \(s.rows)")
                    .accessibilityAddTraits(s == item.size ? .isSelected : [])
                    .help(s.title)
                }
            }
            .padding(Space.s1).background(palette.panelStrong, in: coreShape(Radius.control))
            .overlay { coreShape(Radius.control).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
            Spacer(minLength: 0)
            Button {
                shell.removeWidget(item.id)
            } label: {
                Image(systemName: "xmark").font(.system(size: MacTextSize.meta, weight: .semibold))
            }
            .buttonStyle(SizeChoiceStyle(selected: false, destructive: true))
            .background(palette.panelStrong, in: coreShape(Radius.chip))
            .overlay { coreShape(Radius.chip).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
            .accessibilityLabel("Remove \(item.kind.title)")
            .help("Remove")
        }
        .padding(Space.s2)
        .opacity(editing ? 1 : 0)
        .allowsHitTesting(editing)
        .disabled(!editing)
        .accessibilityHidden(!editing)
        .animation(Motion.out(Motion.ui), value: editing)
    }

    private func sizeMark(_ s: WidgetSize) -> some View {
        coreShape(1.5).frame(
            width: CGFloat(5 * s.cols + 2 * (s.cols - 1)), height: CGFloat(5 * s.rows + 2 * (s.rows - 1))
        )
        .opacity(0.85)
    }
}

/// 22 pt square choice (`.wd-sz`): hover tint; the chosen size is a blue tint with an edge, so it never rests on colour alone.
struct SizeChoiceStyle: ButtonStyle {
    let selected: Bool
    var destructive = false
    @Environment(\.corePalette) private var palette
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                selected ? palette.primary : hovering && destructive ? palette.tone(.fail).ink : palette.text2
            )
            .frame(minWidth: MacSize.controlSm, minHeight: MacSize.controlSm)
            .background(selected ? palette.navActive : hovering ? palette.uDim : .clear, in: coreShape(Radius.chip))
            .overlay { if selected { coreShape(Radius.chip).strokeBorder(palette.navActiveEdge, lineWidth: 1) } }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Motion.out(Motion.hover), value: hovering)
    }
}
