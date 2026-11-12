import SwiftUI

// Shared parts every screen used to hand-build: a count badge, a wizard step bar, a labelled back button and a choice
// row. All rounded rectangles on the CoreUI radii, none of them a pill or a circle.

/// How loud a count is: blue for a count, amber for "needs you", quiet for a number that is only information.
public enum CountTone: Sendable { case accent, needsYou, quiet }

/// A small count in a rounded rectangle (sidebar, filter tiles, section headers). One height and one radius, everywhere.
/// Nothing shows for 0 unless `showsZero`; above 99 it reads "99+".
public struct CountBadge: View {
    let count: Int
    let tone: CountTone
    let showsZero: Bool
    let label: String?
    @Environment(\.corePalette) private var palette

    /// `label` is what VoiceOver says after the number ("AI sessions need you" -> "3, AI sessions need you").
    public init(_ count: Int, tone: CountTone = .accent, showsZero: Bool = false, label: String? = nil) {
        self.count = count
        self.tone = tone
        self.showsZero = showsZero
        self.label = label
    }

    public var body: some View {
        if count > 0 || showsZero {
            Text(count > 99 ? "99+" : "\(count)")
                .coreFont(size: MacTextSize.meta, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(ink)
                .padding(.horizontal, Space.s1 + 2)
                .frame(minWidth: MacSize.chip, minHeight: MacSize.chip)
                .background(fill, in: coreShape(Radius.chip))
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label.map { "\(count), \($0)" } ?? "\(count)")
        }
    }

    private var fill: Color {
        switch tone {
        case .accent: palette.btnPrimary
        case .needsYou: GlassInk.amber
        case .quiet: palette.uDim
        }
    }

    private var ink: Color { tone == .needsYou ? .black.opacity(0.78) : tone == .quiet ? palette.text2 : .white }
}

/// Where a wizard stands: one rounded bar per step (done and current fill blue), the step names under them, the
/// current one in full ink. `showsCount` adds a quiet "Step 3 of 4" above, for long names or few of them.
public struct CoreStepper: View {
    let steps: [String]
    let at: Int
    let showsCount: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    public init(_ steps: [String], at: Int, showsCount: Bool = false) {
        self.steps = steps
        self.at = min(max(at, 0), max(steps.count - 1, 0))
        self.showsCount = showsCount
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if showsCount {
                Text("Step \(at + 1) of \(steps.count)").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
            HStack(spacing: Space.s2) {
                ForEach(steps.indices, id: \.self) { i in
                    coreShape(2).fill(i <= at ? palette.primary : palette.track).frame(height: Space.s1)
                }
            }
            .animation(reduce ? nil : Motion.out(Motion.ui), value: at)
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                ForEach(steps.indices, id: \.self) { i in
                    Text("\(i + 1) \(steps[i])")
                        .coreFont(size: MacTextSize.meta, weight: i == at ? .semibold : .regular)
                        .foregroundStyle(i == at ? palette.text : palette.text2.opacity(0.7))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(at + 1) of \(steps.count)")
        .accessibilityValue(steps.indices.contains(at) ? steps[at] : "")
    }
}

/// "‹ Runners": the way back to the list a page came from. A symbol and the list's name, never an icon alone.
public struct BackButton: View {
    let title: String
    let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: "chevron.left")
        }
        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
        .help("Back to \(title)")
        .accessibilityLabel("Back to \(title)")
    }
}

/// One choice among a few, as a rounded rectangle: the chosen one gets the blue edge and a lifted fill. No radio circle.
/// Put several in a `VStack(spacing: 2)`; the trailing view carries a state or a count.
public struct RadioRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let symbol: String?
    let selected: Bool
    let action: () -> Void
    let trailing: Trailing

    public init(
        _ title: String, subtitle: String? = nil, symbol: String? = nil, selected: Bool, action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.selected = selected
        self.action = action
        self.trailing = trailing()
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                if let symbol {
                    Image(systemName: symbol).coreFont(size: MacTextSize.title)
                        .frame(width: Space.s6, height: Space.s6).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(1)
                    if let subtitle { RadioSubtitle(text: subtitle) }
                }
                Spacer(minLength: Space.s2)
                trailing
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
            .frame(minHeight: Space.s8 + Space.s2)
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(RadioRowStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension RadioRow where Trailing == EmptyView {
    public init(
        _ title: String, subtitle: String? = nil, symbol: String? = nil, selected: Bool, action: @escaping () -> Void
    ) {
        self.init(title, subtitle: subtitle, symbol: symbol, selected: selected, action: action) { EmptyView() }
    }
}

private struct RadioSubtitle: View {
    let text: String
    @Environment(\.corePalette) private var palette
    var body: some View {
        Text(text).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(1)
    }
}

private struct RadioRowStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        RadioRowSurface(configuration: configuration, selected: selected)
    }
}

private struct RadioRowSurface: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.coreForcedInteraction) private var forced
    @State private var hovering = false

    private var pressed: Bool { configuration.isPressed || forced == .pressed }
    private var hover: Bool { hovering || forced == .hover }

    var body: some View {
        let shape = coreShape(Radius.row)
        configuration.label
            .foregroundStyle(palette.text)
            .background(selected ? palette.uDimHover : hover || pressed ? palette.uDim : .clear, in: shape)
            .overlay { if selected { shape.strokeBorder(palette.primary, lineWidth: 1.5) } }
            .coreDimWhenDisabled(enabled)
            .scaleEffect(pressed && !reduce ? 0.985 : 1)
            .coreAnimation(Motion.press(Motion.press), value: pressed)
            .animation(Motion.out(Motion.hover), value: hover)
            .animation(Motion.out(Motion.hover), value: selected)
            .onHover { hovering = $0 }
    }
}
