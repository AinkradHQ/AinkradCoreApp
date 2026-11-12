import SwiftUI

/// A whole number with − and + beside it in one quiet well (the AI-sessions-at-once row). Hover and press come from the
/// buttons; an end of the range disables its button. Focus it and Up/Right add `step`, Down/Left take it away.
/// Every change is clamped to `range` before it is sent.
public struct CoreNumberStepper: View {
    let value: Int
    let range: ClosedRange<Int>
    let step: Int
    let noun: String
    let set: (Int) -> Void
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.coreForcedInteraction) private var forced
    @FocusState private var focused: Bool

    /// `noun` completes the help and VoiceOver words: "Fewer AI sessions at the same time".
    public init(
        value: Int, in range: ClosedRange<Int>, step: Int = 1, noun: String, set: @escaping (Int) -> Void
    ) {
        self.value = value
        self.range = range
        self.step = max(1, step)
        self.noun = noun
        self.set = set
    }

    public init(value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1, noun: String) {
        self.init(value: value.wrappedValue, in: range, step: step, noun: noun) { value.wrappedValue = $0 }
    }

    /// `value` moved by `delta` and held inside `range`.
    static func moved(_ value: Int, by delta: Int, in range: ClosedRange<Int>) -> Int {
        min(max(value + delta, range.lowerBound), range.upperBound)
    }

    private func move(_ delta: Int) {
        let next = Self.moved(value, by: delta, in: range)
        if next != value { set(next) }
    }

    public var body: some View {
        HStack(spacing: 0) {
            Button {
                move(-step)
            } label: {
                Image(systemName: "minus").frame(width: MacSize.controlMd)
            }
            .disabled(value <= range.lowerBound).help("Fewer \(noun)").accessibilityLabel("Fewer \(noun)")
            Text("\(value)").coreFont(size: MacTextSize.body, weight: .semibold).monospacedDigit()
                .frame(minWidth: Space.s6).contentTransition(.numericText())
            Button {
                move(step)
            } label: {
                Image(systemName: "plus").frame(width: MacSize.controlMd)
            }
            .disabled(value >= range.upperBound).help("More \(noun)").accessibilityLabel("More \(noun)")
        }
        .buttonStyle(CoreButtonStyle(.plain, size: .small))
        .coreWell(radius: Radius.control)
        .coreFocusRing(focused || forced == .focused, radius: Radius.control, palette: palette)
        .coreDimWhenDisabled(enabled)
        .fixedSize()
        .focusable(enabled).focused($focused).focusEffectDisabled()
        .onKeyPress(.upArrow) {
            move(step)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            move(step)
            return .handled
        }
        .onKeyPress(.downArrow) {
            move(-step)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            move(-step)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(step)
            case .decrement: move(-step)
            @unknown default: break
            }
        }
    }
}
