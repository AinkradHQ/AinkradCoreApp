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
        // Choices keep their full names: they size to content and wrap onto another row when they do not fit.
        ChoiceFlow(spacing: Space.s2, fill: fill) {
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

/// Lays choices out at their natural width and wraps to a new row when the next one will not fit. With `fill`, a set that
/// fits one row shares the width equally; a wrapped set stretches each row to the full width.
struct ChoiceFlow: Layout {
    let spacing: CGFloat
    let fill: Bool

    private func rows(_ subviews: Subviews, width: CGFloat) -> (rows: [[Int]], sizes: [CGSize]) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var rows: [[Int]] = [[]]
        var used: CGFloat = 0
        for (i, size) in sizes.enumerated() {
            let need = (rows[rows.count - 1].isEmpty ? 0 : spacing) + size.width
            if used + need > width, !rows[rows.count - 1].isEmpty {
                rows.append([i])
                used = size.width
            } else {
                rows[rows.count - 1].append(i)
                used += need
            }
        }
        return (rows, sizes)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let (rows, sizes) = rows(subviews, width: width)
        let heights = rows.map { r in r.map { sizes[$0].height }.max() ?? 0 }
        let height = heights.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let widest =
            rows.map { r in r.reduce(CGFloat(0)) { $0 + sizes[$1].width } + spacing * CGFloat(r.count - 1) }.max() ?? 0
        return CGSize(width: fill && proposal.width != nil ? width : widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (rows, sizes) = rows(subviews, width: bounds.width)
        let count = CGFloat(subviews.count)
        let maxW = sizes.map(\.width).max() ?? 0
        let equal = fill && count * maxW + spacing * (count - 1) <= bounds.width
        var y = bounds.minY
        for row in rows {
            let n = CGFloat(row.count)
            let natural = row.reduce(CGFloat(0)) { $0 + sizes[$1].width } + spacing * (n - 1)
            let extra = fill && !equal ? max(0, bounds.width - natural) / n : 0
            let share = (bounds.width - spacing * (n - 1)) / n
            let h = row.map { sizes[$0].height }.max() ?? 0
            var x = bounds.minX
            for i in row {
                let w = equal ? share : sizes[i].width + extra
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: w, height: h))
                x += w + spacing
            }
            y += h + spacing
        }
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
                        .accessibilityHidden(true)
                }
                Text(segment.title).font(.system(size: MacTextSize.body, weight: .semibold)).lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(.white.opacity(selected || hovering ? 1 : 0.8))
            .padding(.horizontal, Space.s3)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: MacSize.controlMd + 4)
            .background {
                if selected {
                    coreShape(Radius.control).fill(GlassInk.blue.opacity(0.8))
                        .matchedGeometryEffect(id: "lens", in: lens)
                } else {
                    coreShape(Radius.control).fill(hovering ? GlassInk.wellHover : GlassInk.well)
                }
            }
            .overlay {
                coreShape(Radius.control).strokeBorder(.white.opacity(selected ? 0.3 : 0.15), lineWidth: 1)
            }
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .scaleEffect(pressed ? 0.97 : 1)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false }
        )
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .animation(Motion.press(Motion.press), value: pressed)
        .animation(Motion.out(Motion.move), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// An on/off setting as a glass tile in the segment look (Ahmed, 2026-11-05): its icon swaps and bounces, a small
/// rounded switch slides inside, and it lights blue when on. Hover changes the fill; a press dips it.
public struct GlassToggleTile: View {
    let title: String
    let sub: String?
    let symbol: String
    let onSymbol: String
    let fill: Bool
    @Binding var isOn: Bool
    @State private var hovering = false
    @State private var pressed = false
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
                    .font(.system(size: sub == nil ? MacTextSize.body : MacTextSize.title, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isOn)
                    .frame(width: sub == nil ? nil : 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
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
                coreShape(Radius.control).fill(hovering ? GlassInk.wellHover : GlassInk.well)
            }
            .overlay { coreShape(Radius.control).strokeBorder(.white.opacity(0.15), lineWidth: 1) }
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .scaleEffect(pressed ? 0.97 : 1)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false }
        )
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .animation(Motion.press(Motion.press), value: pressed)
        .animation(Motion.out(Motion.move), value: isOn)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    /// A small rounded switch: the knob slides and the track fills.
    private var knob: some View {
        coreShape(4).fill(isOn ? GlassInk.blue : .white.opacity(0.12))
            .frame(width: 30, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                coreShape(4).fill(.white).frame(width: 14, height: 14).padding(2)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .accessibilityHidden(true)
    }
}
