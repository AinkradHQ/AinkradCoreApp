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
    private var radius: CGFloat { 26 }

    var body: some View {
        let size = DeskGrid.frameSize(item.size)
        ZStack(alignment: .topLeading) {
            WidgetBody(kind: item.kind, size: item.size, shell: shell)
                .padding(18).padding(.top, editing ? 30 : 0)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                // The edit padding snaps (re-laying out a widget every frame was the cost); the fade below still animates.
                .transaction(value: editing) { $0.animation = nil }
                .opacity(editing ? 0.5 : 1)
                .allowsHitTesting(!editing)
                .animation(.easeOut(duration: 0.2), value: editing)
            chrome
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(coreShape(radius))
        // By day the clear glass lets the bright sky through, so white ink measured 2.2 to 3.5:1. The panes' day look is a dark
        // layer under the glass; the widgets get the same one (night is unchanged). Contrast measured 2026-11-09.
        .background(Color.black.opacity(palette.isDay ? 0.6 : 0), in: coreShape(radius))
        // Apple's Liquid Glass draws its own edge and light; no extra stroke or ring on top.
        .coreGlass(radius: radius, interactive: false, tinted: false)
        .overlay {
            coreShape(radius).fill(Color.white.opacity(hovering && !lifting ? 0.04 : 0)).allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
        // The lifted shadow is a second layer that fades in; its radius never animates.
        .shadow(color: .black.opacity(lifting ? 0.3 : 0), radius: 30, y: 14)
        .scaleEffect(lifting && !reduce ? 1.025 : 1)
        .animation(.easeOut(duration: 0.2), value: lifting)
        .animation(.easeOut(duration: 0.24), value: hovering)
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
        .coreActivates(enabled: item.kind.launch != nil) { if !editing { open() } }
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
        switch p.key {
        case .leftArrow: shell.moveWidget(item.id, dx: -1, dy: 0)
        case .rightArrow: shell.moveWidget(item.id, dx: 1, dy: 0)
        case .upArrow: shell.moveWidget(item.id, dx: 0, dy: -1)
        case .downArrow: shell.moveWidget(item.id, dx: 0, dy: 1)
        case .delete, .deleteForward: shell.removeWidget(item.id)
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
        Divider()
        Button(editing ? "Done Editing" : "Edit Widgets") { shell.editingWidgets.toggle() }
        Button("Add Widget…") { shell.addingWidget = true }
        Divider()
        Button("Remove", role: .destructive) { shell.removeWidget(item.id) }
    }

    /// `.wd-edit`: the size choices at the top left, remove at the top right. They fade in; they are Tab stops only while editing.
    private var chrome: some View {
        HStack {
            HStack(spacing: 3) {
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
            .padding(3).background(palette.panelStrong, in: coreShape(9))
            .overlay { coreShape(9).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
            Spacer(minLength: 0)
            Button {
                shell.removeWidget(item.id)
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(SizeChoiceStyle(selected: false, destructive: true))
            .background(palette.panelStrong, in: coreShape(6))
            .overlay { coreShape(6).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
            .accessibilityLabel("Remove \(item.kind.title)")
            .help("Remove")
        }
        .padding(8)
        .opacity(editing ? 1 : 0)
        .allowsHitTesting(editing)
        .disabled(!editing)
        .accessibilityHidden(!editing)
        .animation(.easeOut(duration: 0.2), value: editing)
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
            .frame(minWidth: 22, minHeight: 22)
            .background(selected ? palette.navActive : hovering ? palette.uDim : .clear, in: coreShape(6))
            .overlay { if selected { coreShape(6).strokeBorder(palette.navActiveEdge, lineWidth: 1) } }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Motion.out(Motion.hover), value: hovering)
    }
}
