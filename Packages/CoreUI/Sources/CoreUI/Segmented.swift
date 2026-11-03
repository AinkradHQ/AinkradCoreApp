import SwiftUI

public struct CoreSegment<ID: Hashable & Sendable>: Identifiable, Sendable {
    public let id: ID
    public let title: String
    public let symbol: String?
    public init(_ id: ID, _ title: String, symbol: String? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
    }
}

/// Segmented control. One tab stop; Left/Right (and Up/Down) move the selection, Home/End jump. States: selected, hover, focus, disabled.
public struct CoreSegmented<ID: Hashable & Sendable>: View {
    let segments: [CoreSegment<ID>]
    @Binding var selection: ID
    let label: String
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.coreForcedInteraction) private var forced
    @FocusState private var focused: Bool
    @Namespace private var lens

    public init(_ label: String, segments: [CoreSegment<ID>], selection: Binding<ID>) {
        self.label = label
        self.segments = segments
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: Space.s1 / 2) {
            ForEach(segments) { seg in
                Segment(segment: seg, selected: seg.id == selection, lens: lens) { selection = seg.id }
            }
        }
        .padding(Space.s1 / 2)
        .background(palette.uDim, in: coreShape(Radius.control))
        .coreFocusRing(focused || forced == .focused, radius: Radius.control, palette: palette)
        .opacity(enabled ? 1 : 0.45)
        .focusable(enabled)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.home) { jump(0) }
        .onKeyPress(.end) { jump(segments.count - 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityAdjustableAction { direction in _ = move(direction == .increment ? 1 : -1) }
        .coreAnimation(Motion.out(Motion.move), value: selection)
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard let i = segments.firstIndex(where: { $0.id == selection }) else { return .ignored }
        return jump(min(max(i + step, 0), segments.count - 1))
    }

    private func jump(_ index: Int) -> KeyPress.Result {
        guard segments.indices.contains(index) else { return .ignored }
        selection = segments[index].id
        return .handled
    }
}

private struct Segment<ID: Hashable & Sendable>: View {
    let segment: CoreSegment<ID>
    let selected: Bool
    let lens: Namespace.ID
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s1 + Space.s1 / 2) {
                if let symbol = segment.symbol { Image(systemName: symbol).accessibilityHidden(true) }
                Text(segment.title)
            }
            .font(.system(size: MacTextSize.body, weight: .medium))
            .foregroundStyle(selected ? palette.navActiveInk : hovering ? palette.text : palette.text2)
            .padding(.horizontal, Space.s3 - Space.s1 / 2)
            .frame(minHeight: MacSize.controlMd - Space.s1)
            .background {
                if selected {
                    coreShape(Radius.chip)
                        .fill(palette.navActive)
                        .overlay { coreShape(Radius.chip).strokeBorder(palette.navActiveEdge, lineWidth: 1) }
                        .matchedGeometryEffect(id: "lens", in: lens)
                } else if hovering {
                    coreShape(Radius.chip).fill(palette.uDim)
                }
            }
            .contentShape(coreShape(Radius.chip))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
