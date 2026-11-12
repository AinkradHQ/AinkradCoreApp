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

    /// The pane radius (rect.css cards 16): a rounded rectangle, never a pill.
    private var radius: CGFloat { Radius.pane }

    var body: some View {
        let size = DeskGrid.frameSize(item.size)
        ZStack(alignment: .topLeading) {
            WidgetBody(kind: item.kind, size: item.size, shell: shell)
                .padding(Space.s4)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                // The edit chrome floats over the content; nothing moves, so nothing is cut off at the bottom.
                .opacity(editing ? 0.5 : 1)
                .allowsHitTesting(!editing)
                .animation(.easeOut(duration: 0.2), value: editing)
            chrome
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(coreShape(radius))
        // By day the clear glass lets the bright sky through, so white ink measured 2.2 to 3.5:1. The panes' day look is a dark
        // layer under the glass; the widgets get the same one (night is unchanged). Contrast measured 2026-11-09.
        .background(palette.isDay ? Color.white.opacity(0.45) : Color.black.opacity(0), in: coreShape(radius))
        // Apple's Liquid Glass draws its own edge and light; no extra stroke or ring on top.
        .coreGlass(radius: radius, interactive: false, tinted: false)
        .overlay {
            coreShape(radius).fill(Color.white.opacity(hovering && !lifting ? (palette.isDay ? 0.15 : 0.04) : 0))
                .allowsHitTesting(false)
        }
        .shadow(color: GlassInk.shade(0.12), radius: 14, y: 4)
        // The lifted shadow is a second layer that fades in; its radius never animates.
        .shadow(color: GlassInk.shade(lifting ? 0.3 : 0), radius: 30, y: 14)
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
                    Text("\(s.title) · \(s.cols / 2)×\(s.rows / 2)")
                    if s == item.size { Image(systemName: "checkmark") }
                }
            }
        }
        clockMenu
        Divider()
        Button(editing ? "Done Editing" : "Edit Widgets") { shell.editingWidgets.toggle() }
        Button("Add Widget…") { shell.addingWidget = true }
        Divider()
        Button("Remove", role: .destructive) { shell.removeWidget(item.id) }
    }

    /// The clock settings, where the clock is (the same ones are in Settings → Clocks).
    @ViewBuilder private var clockMenu: some View {
        @Bindable var prefs = ClockPrefs.shared
        if item.kind == .clock {
            Picker("Second Hand", selection: $prefs.secondHand) {
                ForEach(SecondHand.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        } else if item.kind == .digital {
            Toggle("Show Seconds", isOn: $prefs.showsSeconds)
        }
    }

    /// `.wd-edit`: the size choices at the top left, remove at the top right. They fade in; they are Tab stops only while editing.
    private var chrome: some View {
        HStack {
            HStack(spacing: 2) {
                ForEach(item.kind.sizes, id: \.self) { s in
                    Button {
                        shell.resizeWidget(item.id, to: s)
                    } label: {
                        sizeMark(s)
                    }
                    .buttonStyle(SizeChoiceStyle(selected: s == item.size))
                    .accessibilityLabel(s.spoken)
                    .accessibilityAddTraits(s == item.size ? .isSelected : [])
                    .help(s.spoken)
                }
            }
            .padding(2).background(palette.panelStrong, in: coreShape(Radius.control))
            .overlay { coreShape(Radius.control).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
            Spacer(minLength: 0)
            Button {
                shell.removeWidget(item.id)
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
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
        .animation(.easeOut(duration: 0.2), value: editing)
    }

    private func sizeMark(_ s: WidgetSize) -> some View {
        // Drawn in Home cells (2 x 2 units each): a small is one square, a wide two side by side.
        coreShape(2).frame(width: CGFloat(8 * (s.cols / 2) - 2), height: CGFloat(8 * (s.rows / 2) - 2))
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
