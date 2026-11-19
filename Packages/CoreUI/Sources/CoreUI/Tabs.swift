import SwiftUI

public struct CoreTab<ID: Hashable & Sendable>: Identifiable, Sendable {
    public let id: ID
    public let title: String
    public init(_ id: ID, _ title: String) {
        self.id = id
        self.title = title
    }
}

/// Top tabs of a pane: text tabs in a rounded track, the selection glides between them. One tab stop; Left/Right move,
/// Home/End jump. Reduce Motion: the selection jumps and fades in place.
public struct CoreTabs<ID: Hashable & Sendable>: View {
    let tabs: [CoreTab<ID>]
    @Binding var selection: ID
    let label: String
    @Environment(\.isEnabled) private var enabled
    @FocusState private var focused: Bool
    @Namespace private var glide

    public init(_ label: String, tabs: [CoreTab<ID>], selection: Binding<ID>) {
        self.label = label
        self.tabs = tabs
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: Space.s1 / 2) {
            ForEach(tabs) { tab in
                TabItem(title: tab.title, selected: tab.id == selection, glide: glide) { selection = tab.id }
            }
        }
        .padding(Space.s1 / 2)
        .background(GlassInk.well, in: coreShape(Radius.control + Space.s1 / 2))
        .coreDimWhenDisabled(enabled)
        .focusable(enabled)
        .focused($focused)
        .focusEffectDisabled()
        .coreSideKeys { move($0) }
        .onKeyPress(.home) { jump(0) }
        .onKeyPress(.end) { jump(tabs.count - 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityAdjustableAction { direction in _ = move(direction == .increment ? 1 : -1) }
        .coreAnimation(Motion.out(Motion.move), value: selection)
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard let i = tabs.firstIndex(where: { $0.id == selection }) else { return .ignored }
        return jump(min(max(i + step, 0), tabs.count - 1))
    }

    private func jump(_ index: Int) -> KeyPress.Result {
        guard tabs.indices.contains(index) else { return .ignored }
        selection = tabs[index].id
        return .handled
    }
}

private struct TabItem: View {
    let title: String
    let selected: Bool
    let glide: Namespace.ID
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                .foregroundStyle(GlassInk.primary.opacity(selected || hovering ? 1 : 0.7))
                .padding(.horizontal, Space.s3)
                .frame(minHeight: MacSize.controlMd)
                .background {
                    if !selected && hovering { coreShape(Radius.control).fill(GlassInk.well) }
                }
                .background {
                    if reduce {
                        coreShape(Radius.control).fill(GlassInk.wellHover.opacity(selected ? 1 : 0))
                    } else if selected {
                        coreShape(Radius.control).fill(GlassInk.wellHover).matchedGeometryEffect(id: "tab", in: glide)
                    }
                }
                .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(CoreTilePress())
        .focusable(false)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
