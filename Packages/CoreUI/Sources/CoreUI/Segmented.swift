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

/// An on/off setting as a glass tile in the segment look (Ahmed, 2026-11-05): its icon swaps and bounces, a small
/// rounded switch slides inside, and it lights blue when on. Hover lifts it; a press springs.
public struct GlassToggleTile: View {
    let title: String
    let sub: String?
    let symbol: String
    let onSymbol: String
    let fill: Bool
    @Binding var isOn: Bool
    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    public init(
        _ title: String, sub: String? = nil, symbol: String, onSymbol: String? = nil, isOn: Binding<Bool>,
        fill: Bool = false
    ) {
        self.title = title
        self.sub = sub
        self.symbol = symbol
        self.onSymbol = onSymbol ?? symbol
        self.fill = fill
        self._isOn = isOn
    }

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: isOn ? onSymbol : symbol)
                    .font(.system(size: sub == nil ? MacTextSize.body : MacTextSize.headline + 2, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isOn)
                    .symbolEffect(.pulse, options: .repeating, isActive: isOn && !reduce && sub == nil)
                    .frame(width: sub == nil ? nil : 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: MacTextSize.body, weight: .semibold)).lineLimit(1)
                    if let sub {
                        Text(sub).font(.system(size: MacTextSize.meta)).foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if fill { Spacer(minLength: Space.s2) }
                knob
            }
            .foregroundStyle(.white.opacity(isOn || hovering ? 1 : 0.8))
            .padding(.horizontal, Space.s3).padding(.vertical, sub == nil ? 0 : Space.s3)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: MacSize.controlMd + 4)
            .background {
                coreShape(Radius.control)
                    .fill(isOn ? GlassInk.blue.opacity(0.8) : hovering ? GlassInk.slate.opacity(0.28) : GlassInk.well)
                    .shadow(color: GlassInk.blue.opacity(isOn ? 0.45 : 0), radius: 10)
            }
            .overlay { coreShape(Radius.control).strokeBorder(.white.opacity(isOn ? 0.3 : 0.15), lineWidth: 1) }
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .scaleEffect(pressed ? 0.96 : hovering ? 1.03 : 1)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false }
        )
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25, bounce: 0.3), value: hovering)
        .animation(.spring(duration: 0.2, bounce: 0.4), value: pressed)
        .animation(.spring(duration: 0.35, bounce: 0.35), value: isOn)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    /// A small rounded switch: the knob slides and the track fills.
    private var knob: some View {
        coreShape(5).fill(.white.opacity(isOn ? 0.35 : 0.12))
            .frame(width: 30, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                coreShape(4).fill(.white).frame(width: 14, height: 14).padding(2)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .accessibilityHidden(true)
    }
}
