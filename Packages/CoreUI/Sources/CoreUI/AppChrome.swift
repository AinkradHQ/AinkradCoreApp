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
    public init(style: AppSurfaceStyle, opacity: Double, tint: Color, blur: Bool = true) {
        self.style = style
        self.opacity = opacity
        self.tint = tint
        self.blur = blur
    }
    public var body: some View {
        let shape = coreShape(Radius.cardMac)
        Group {
            switch style {
            case .clear: shape.fill(.black.opacity(opacity * 0.6))
            case .frosted: shape.fill(.ultraThinMaterial).overlay { shape.fill(.black.opacity(opacity * 0.6)) }
            case .tinted:
                ZStack {
                    if blur { shape.fill(.ultraThinMaterial) }
                    shape.fill(tint.opacity(opacity))
                }
            case .solid: shape.fill(Color(red: 0.05, green: 0.06, blue: 0.09).opacity(0.5 + opacity * 0.5))
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.25), value: style)
        .animation(.easeOut(duration: 0.25), value: opacity)
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
                Text(title).font(.system(size: MacTextSize.body, weight: on ? .semibold : .regular))
                Text("\(count)").font(.system(size: MacTextSize.meta, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 6).frame(minHeight: 18)
                    .background(.white.opacity(on ? 0.22 : 0.1), in: coreShape(5))
                    .contentTransition(.numericText())
                if hovering || on {
                    Text(key).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(
                        GlassInk.secondary)
                }
            }
            .foregroundStyle(on ? GlassInk.primary : GlassInk.secondary)
            .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd + 4)
            .background(
                on ? .white.opacity(0.16) : hovering ? .white.opacity(0.07) : .clear, in: coreShape(Radius.control)
            )
            .overlay { if on { coreShape(Radius.control).strokeBorder(.white.opacity(0.25), lineWidth: 1) } }
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: on)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A header action: an icon that bounces on hover (or pulses while something waits), a word and its key.
public struct AppActionTile: View {
    let title: String
    let symbol: String
    let key: String
    let hue: Color
    let prominent: Bool
    let pulse: Bool
    let run: () -> Void
    @State private var hovering = false
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
                Image(systemName: symbol).font(.system(size: MacTextSize.body, weight: .semibold))
                    .symbolEffect(.bounce, value: hovering)
                    .symbolEffect(.pulse, options: .repeating, isActive: pulse)
                Text(title).font(.system(size: MacTextSize.body, weight: .semibold)).lineLimit(1)
                Text(key).font(.system(size: 10, weight: .medium, design: .rounded))
                    .padding(.horizontal, 5).frame(minHeight: 16).background(.white.opacity(0.16), in: coreShape(4))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd + 4)
            .background(
                prominent || pulse ? hue.opacity(hovering ? 0.95 : 0.8) : hovering ? hue.opacity(0.28) : GlassInk.well,
                in: coreShape(Radius.control)
            )
            .overlay { coreShape(Radius.control).strokeBorder(.white.opacity(prominent ? 0.3 : 0.15), lineWidth: 1) }
            .shadow(color: hue.opacity(hovering || pulse ? 0.45 : 0), radius: 10)
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .scaleEffect(hovering ? 1.04 : 1)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25, bounce: 0.3), value: hovering)
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
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(hue)
            Text(text).monospacedDigit()
        }
        .font(.system(size: MacTextSize.meta, weight: .medium))
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
