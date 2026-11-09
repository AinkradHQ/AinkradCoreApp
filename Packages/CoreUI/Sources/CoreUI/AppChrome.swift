import SwiftUI

/// The parts every app (Terminals, Agents, …) is built from, so they look the same (Ahmed, 2026-11-05: "unify the look,
/// keep the terminal version"): the surface inside the pane's glass rim, the header's filter and action tiles, and the
/// footer's status chips and key line.

/// The app's surface style.
public enum AppSurfaceStyle: String, CaseIterable, Sendable { case clear, frosted, tinted, solid }

/// The app's background inside the pane's glass rim, rounded. `tint` colours the tinted style (a terminal theme's
/// background, the agents violet).
public struct AppSurfaceFill: View {
    let style: AppSurfaceStyle
    let opacity: Double
    let tint: Color
    let blur: Bool
    let radius: CGFloat
    @Environment(\.coreSolidOnly) private var solidOnly
    /// The one tint every app's surface uses (Ahmed, 2026-11-05: the same settings must look the same in every app).
    /// The Terminals app's Deep Blue.
    public static let tint = Color(red: 3 / 255, green: 8 / 255, blue: 16 / 255)
    /// The Solid look's colour.
    public static let solid = Color(red: 0.05, green: 0.06, blue: 0.09)
    public init(
        style: AppSurfaceStyle, opacity: Double, tint: Color = AppSurfaceFill.tint, blur: Bool = true,
        radius: CGFloat = Radius.cardMac
    ) {
        self.style = style
        self.opacity = opacity
        self.tint = tint
        self.blur = blur
        self.radius = radius
    }
    /// One Look (Settings, Appearance, or an app's own) as a fill.
    public init(_ look: CoreLook, tint: Color = AppSurfaceFill.tint, radius: CGFloat = Radius.cardMac) {
        self.init(style: look.mode.style, opacity: look.opacity, tint: tint, blur: look.mode.blur, radius: radius)
    }
    public var body: some View {
        let shape = coreShape(radius)
        // Blur is its own choice: any style can sit on frosted glass (Blurred) or over the sky as it is (Clear).
        ZStack {
            if solidOnly {
                shape.fill(Self.solid)
            } else {
                if blur { shape.fill(.ultraThinMaterial) }
                // Only three looks are offered (Blurred, Clear, Solid); a stored clear or frosted from before draws as
                // the tint, so the same choice looks the same in every app.
                if style == .solid {
                    shape.fill(Self.solid.opacity(0.5 + opacity * 0.5))
                } else {
                    shape.fill(tint.opacity(opacity))
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(Motion.out(Motion.ui), value: style)
        .animation(Motion.out(Motion.ui), value: opacity)
        .animation(Motion.out(Motion.ui), value: blur)
    }
}

/// A header filter: glass tile with its count and key; the lit one is white glass.
public struct AppFilterTile: View {
    let title: String
    let count: Int
    let on: Bool
    let key: String
    let pick: () -> Void
    @State private var hovering = false
    public init(title: String, count: Int, on: Bool, key: String, pick: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.on = on
        self.key = key
        self.pick = pick
    }
    public var body: some View {
        Button(action: pick) {
            HStack(spacing: Space.s2) {
                Text(title).coreFont(size: MacTextSize.body, weight: on ? .semibold : .regular)
                if count >= 0 {  // a negative count hides the badge (a page with nothing to count)
                    Text("\(count)").coreFont(size: MacTextSize.meta, weight: .semibold).monospacedDigit()
                        .padding(.horizontal, 6).frame(minHeight: 18)
                        .background(.white.opacity(on ? 0.22 : 0.1), in: coreShape(5))
                        .contentTransition(.numericText())
                }
                // Always laid out, shown by opacity: hover never changes the tile's width.
                Text(key).coreFont(size: 10, weight: .medium, design: .rounded).foregroundStyle(
                    GlassInk.secondary
                )
                .opacity(hovering || on ? 1 : 0)
                .accessibilityHidden(true)
            }
            .foregroundStyle(on ? GlassInk.primary : GlassInk.secondary)
            .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd + 4)
            .background(
                on ? .white.opacity(0.16) : hovering ? .white.opacity(0.07) : .clear, in: coreShape(Radius.control)
            )
            .overlay {
                if on || hovering {
                    coreShape(Radius.control).strokeBorder(.white.opacity(on ? 0.4 : 0.3), lineWidth: 1)
                }
            }
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(CoreTilePress())
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: on)
        .animation(Motion.out(Motion.hover), value: hovering)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A header action: an icon that bounces once on hover (or pulses while something waits), a word and its key.
public struct AppActionTile: View {
    let title: String
    let symbol: String
    let key: String
    let hue: Color
    let prominent: Bool
    let pulse: Bool
    let run: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    public init(
        title: String, symbol: String, key: String, hue: Color, prominent: Bool = false, pulse: Bool = false,
        run: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.key = key
        self.hue = hue
        self.prominent = prominent
        self.pulse = pulse
        self.run = run
    }
    public var body: some View {
        Button(action: run) {
            HStack(spacing: Space.s2) {
                Image(systemName: symbol).coreFont(size: MacTextSize.body, weight: .semibold)
                    .coreEnterBounce(hovering)
                    .symbolEffect(.pulse, options: .repeating, isActive: pulse && !reduce)
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                if !key.isEmpty {
                    Text(key).coreFont(size: 10, weight: .medium, design: .rounded)
                        .padding(.horizontal, 5).frame(minHeight: 16).background(.white.opacity(0.16), in: coreShape(4))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd + 4)
            .background(
                prominent || pulse ? hue.opacity(hovering ? 0.95 : 0.8) : hovering ? hue.opacity(0.28) : GlassInk.well,
                in: coreShape(Radius.control)
            )
            .overlay {
                coreShape(Radius.control).strokeBorder(
                    .white.opacity(prominent || hovering ? 0.45 : 0.3), lineWidth: 1)
            }
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(CoreTilePress())
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
    }
}

/// A footer status chip: icon in its colour and a count.
public struct AppStatChip: View {
    let symbol: String
    let text: String
    let hue: Color
    public init(_ symbol: String, _ text: String, _ hue: Color) {
        self.symbol = symbol
        self.text = text
        self.hue = hue
    }
    public var body: some View {
        HStack(spacing: Space.s1) {
            Image(systemName: symbol).coreFont(size: 9, weight: .bold).foregroundStyle(hue)
            Text(text).monospacedDigit()
        }
        .coreFont(size: MacTextSize.meta, weight: .medium)
        .padding(.horizontal, Space.s2).frame(height: MacSize.controlSm + 2)
        .background(GlassInk.well, in: coreShape(Radius.chip))
    }
}

/// An app's header: filters at the left and actions at the right on one row when they fit, else the filters on one row
/// and the actions under them, right-aligned. Nothing is squeezed or spills out of the pane.
public struct AppHeader<Filters: View, Actions: View>: View {
    let filters: Filters
    let actions: Actions
    public init(@ViewBuilder filters: () -> Filters, @ViewBuilder actions: () -> Actions) {
        self.filters = filters()
        self.actions = actions()
    }
    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s2) {
                HStack(spacing: Space.s2) { filters }.fixedSize()
                Spacer(minLength: Space.s3)
                HStack(spacing: Space.s2) { actions }.fixedSize()
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                ScrollView(.horizontal) { HStack(spacing: Space.s2) { filters }.fixedSize() }.scrollIndicators(.never)
                HStack(spacing: Space.s2) {
                    Spacer(minLength: 0)
                    actions
                }
            }
        }
        .padding(.horizontal, Space.s4).padding(.top, Space.s2).padding(.bottom, Space.s3)
    }
}

/// The one slider (Ahmed, 2026-11-05: unify): a glass track with a blue fill and a white knob, the two ends named,
/// the value as a percentage at the right. Drag or click anywhere on the track; ← → step by 5 %.
public struct GlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let low: String
    let high: String
    let percent: (Double) -> Int
    let unit: String
    /// Every value lands on a step: 5 % by default, 1 pt for a size.
    let step: Double
    @State private var dragging = false
    @FocusState private var focused: Bool
    @Environment(\.layoutDirection) private var direction

    public init(
        value: Binding<Double>, in range: ClosedRange<Double> = 0...1, low: String, high: String, unit: String = "%",
        step: Double = 0.05, percent: @escaping (Double) -> Int = { Int(($0 * 100).rounded()) }
    ) {
        self.unit = unit
        self.step = step
        self._value = value
        self.range = range
        self.low = low
        self.high = high
        self.percent = percent
    }

    public var body: some View {
        HStack(spacing: Space.s3) {
            Text(low).foregroundStyle(GlassInk.secondary).lineLimit(1)
            GeometryReader { g in
                let f = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                let x = g.size.width * CGFloat(min(max(f, 0), 1))
                ZStack(alignment: .leading) {
                    coreShape(3).fill(.white.opacity(0.14)).frame(height: 6)
                    coreShape(3).fill(GlassInk.blue).frame(width: max(6, x), height: 6)
                    coreShape(6).fill(.white).frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        .offset(x: direction == .rightToLeft ? 9 - x : x - 9)
                }
                .frame(maxHeight: .infinity)
                // Dragging follows the pointer with no easing; only the keyboard path glides (move()).
                .transaction { if dragging { $0.animation = nil } }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { d in
                            dragging = true
                            let along = min(max(d.location.x / max(g.size.width, 1), 0), 1)
                            let t = direction == .rightToLeft ? 1 - along : along
                            let raw = range.lowerBound + Double(t) * (range.upperBound - range.lowerBound)
                            let snapped = min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
                            if snapped != value { value = snapped }
                        }
                        .onEnded { _ in dragging = false })
            }
            .frame(height: 24)
            Text(high).foregroundStyle(GlassInk.secondary).lineLimit(1)
            Text("\(percent(value))\(unit)").coreFont(size: MacTextSize.body, weight: .semibold).monospacedDigit()
                .contentTransition(.numericText()).frame(width: 46, alignment: .trailing)
        }
        .focusable().focused($focused).focusEffectDisabled()
        .coreSideKeys { move(Double($0)) }
        .accessibilityElement()
        .accessibilityLabel("\(low) to \(high)")
        .accessibilityValue("\(percent(value))\(unit == "%" ? " percent" : unit)")
        .accessibilityAdjustableAction { direction in
            _ = move(direction == .increment ? 1 : -1)
        }
    }

    private func move(_ steps: Double) -> KeyPress.Result {
        let next = ((value / step).rounded() + steps) * step
        withAnimation(Motion.out(Motion.hover)) { value = min(max(next, range.lowerBound), range.upperBound) }
        return .handled
    }
}

/// A surface's look in three choices (Ahmed, 2026-11-05), shown at the section's top right; the slider sits below.
/// Blurred: the colour over frosted glass. Clear: the colour over the sky, sharp. Solid: opaque.
public enum SurfaceMode: String, CaseIterable, Sendable {
    case blurred, clear, solid

    public init(style: AppSurfaceStyle, blur: Bool) {
        self = style == .solid ? .solid : blur ? .blurred : .clear
    }
    /// The style and blur this choice stands for.
    public var style: AppSurfaceStyle { self == .solid ? .solid : .tinted }
    public var blur: Bool { self == .blurred }
}

public struct SurfaceModeTabs: View {
    @Binding var mode: SurfaceMode
    public init(mode: Binding<SurfaceMode>) { self._mode = mode }
    public var body: some View {
        CoreSegmented(
            "Look",
            segments: [
                CoreSegment(SurfaceMode.blurred, "Blurred", symbol: "drop.halffull"),
                CoreSegment(.clear, "Clear", symbol: "square.dashed"),
                CoreSegment(.solid, "Solid", symbol: "square.fill"),
            ], selection: $mode)
    }
}

/// A settings row: icon and name at the left, the choices filling the rest (Terminals and Agents Defaults).
public struct SettingRow<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content
    public init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }
    public var body: some View {
        HStack(spacing: Space.s3) {
            Label(title, systemImage: symbol).coreFont(size: MacTextSize.body, weight: .semibold)
                .frame(width: 96, alignment: .leading)
            content
        }
    }
}

/// Where something stands on a short way, as steps (e.g. Off → Test keys → Real keys): the steps passed join in the
/// colour, the current one is lit, a closed one shows a lock.
public struct StepTrack: View {
    let steps: [String]
    let at: Int
    let hue: Color
    let locked: Set<Int>
    public init(_ steps: [String], at: Int, hue: Color, locked: Set<Int> = []) {
        self.steps = steps
        self.at = at
        self.hue = hue
        self.locked = locked
    }
    public var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, name in
                if i > 0 { coreShape(1).fill(i <= at ? GlassInk.blue : GlassInk.track).frame(width: 14, height: 2) }
                HStack(spacing: 4) {
                    if locked.contains(i) { Image(systemName: "lock.fill").coreFont(size: 9) }
                    Text(name)
                }
                .coreFont(size: MacTextSize.meta, weight: i == at ? .semibold : .regular)
                .foregroundStyle(i == at ? .white : GlassInk.secondary)
                .padding(.horizontal, 8).frame(height: 24)
                .background(i == at ? GlassInk.blue.opacity(0.75) : GlassInk.well, in: coreShape(6))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(steps.indices.contains(at) ? steps[at] : "Unknown"), step \(at + 1) of \(steps.count)")
    }
}
