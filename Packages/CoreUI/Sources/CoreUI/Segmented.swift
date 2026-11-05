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
    /// Stretch to the container's width, the segments sharing it equally.
    let fill: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.coreForcedInteraction) private var forced
    @FocusState private var focused: Bool
    @Namespace private var lens

    public init(_ label: String, segments: [CoreSegment<ID>], selection: Binding<ID>, fill: Bool = false) {
        self.label = label
        self.fill = fill
        self.segments = segments
        self._selection = selection
    }

    public var body: some View {
        // Each option is its own glass tile (the section-action look); the picked one lights blue and the light glides.
        HStack(spacing: Space.s2) {
            ForEach(segments) { seg in
                Segment(segment: seg, selected: seg.id == selection, fill: fill, lens: lens) { selection = seg.id }
            }
        }
        .coreFocusRing(focused || forced == .focused, radius: Radius.control, palette: palette)
        .coreDimWhenDisabled(enabled)
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
    let fill: Bool
    let lens: Namespace.ID
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s2) {
                if let symbol = segment.symbol {
                    Image(systemName: symbol).font(.system(size: MacTextSize.body, weight: .semibold))
                        .symbolEffect(.bounce, value: selected)
                        .symbolEffect(.bounce, value: hovering)
                        .accessibilityHidden(true)
                }
                Text(segment.title).font(.system(size: MacTextSize.body, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(selected || hovering ? 1 : 0.8))
            .padding(.horizontal, Space.s3)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: MacSize.controlMd + 4)
            .background {
                if selected {
                    coreShape(Radius.control).fill(GlassInk.blue.opacity(0.8))
                        .shadow(color: GlassInk.blue.opacity(0.45), radius: 10)
                        .matchedGeometryEffect(id: "lens", in: lens)
                } else {
                    coreShape(Radius.control).fill(hovering ? GlassInk.slate.opacity(0.28) : GlassInk.well)
                }
            }
            .overlay {
                coreShape(Radius.control).strokeBorder(.white.opacity(selected ? 0.3 : 0.15), lineWidth: 1)
            }
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .scaleEffect(pressed ? 0.96 : hovering ? 1.04 : 1)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false }
        )
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25, bounce: 0.3), value: hovering)
        .animation(.spring(duration: 0.2, bounce: 0.4), value: pressed)
        .animation(.spring(duration: 0.35, bounce: 0.25), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
