import SwiftUI

/// Progress with no end in sight: a rounded bar with a segment that slides, 30 frames a second. Reduce Motion: the whole
/// bar beats between 0.4 and 1 opacity over `Motion.tick` instead of sliding. Never a circle. The one busy bar; pass a
/// frame width from outside.
public struct CoreBusyBar: View {
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var beat = false
    public init() {}

    public var body: some View {
        Group {
            if reduce {
                coreShape(Space.s1 / 2).fill(palette.primary).opacity(beat ? 1 : 0.4)
                    .animation(.easeInOut(duration: Motion.tick).repeatForever(autoreverses: true), value: beat)
                    .onAppear { beat = true }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate / (Motion.tick * 1.5)
                    let phase = t - t.rounded(.down)
                    GeometryReader { geo in
                        let seg = geo.size.width * 0.3
                        ZStack(alignment: .leading) {
                            coreShape(Space.s1 / 2).fill(palette.track)
                            coreShape(Space.s1 / 2).fill(palette.primary).frame(width: seg)
                                .offset(x: (geo.size.width - seg) * phase)  // grid: ok progress motion, not layout
                        }
                        .clipShape(coreShape(Space.s1 / 2))
                    }
                }
            }
        }
        .frame(height: Space.s1)
        .accessibilityHidden(true)
    }
}

/// One way to tell VoiceOver something happened that no focus change shows (offline, an approval, a failure).
public enum CoreAnnounce {
    public static func post(_ text: String) { AccessibilityNotification.Announcement(text).post() }

    @MainActor private static var pending: [String: Task<Void, Never>] = [:]

    /// Says `text` once nothing newer arrives on the same `channel` for `after`, so a link that flaps is read once.
    @MainActor public static func settled(_ channel: String, _ text: String, after: Duration = .seconds(2)) {
        pending[channel]?.cancel()
        pending[channel] = Task {
            try? await Task.sleep(for: after)
            if !Task.isCancelled { post(text) }
        }
    }
}

extension View {
    /// A tile that opens or picks on tap: VoiceOver reads it as a button and activating it runs the same action.
    public func coreActivates(enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        accessibilityAddTraits(enabled ? .isButton : [])
            .accessibilityAction { if enabled { action() } }
    }
}

// Motion that loops or scales, gated once here so a call site never forgets Reduce Motion.
extension View {
    /// `scaleEffect` that stays at 1 under Reduce Motion.
    public func coreScaleEffect(_ scale: CGFloat, anchor: UnitPoint = .center) -> some View {
        modifier(ReducedScale(scale: scale, anchor: anchor))
    }
    /// A repeating symbol pulse while `active`; still under Reduce Motion.
    public func corePulse(_ active: Bool = true) -> some View {
        modifier(LoopingSymbol(active: active, iterate: false))
    }
    /// A repeating colour sweep through a symbol while `active`; still under Reduce Motion.
    public func coreIterate(_ active: Bool = true) -> some View {
        modifier(LoopingSymbol(active: active, iterate: true))
    }
    /// An animation (usually a repeating one) that does not run under Reduce Motion.
    public func coreLoop<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(ReducedAnimation(animation: animation, value: value))
    }
}

private struct ReducedScale: ViewModifier {
    let scale: CGFloat
    let anchor: UnitPoint
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View { content.scaleEffect(reduce ? 1 : scale, anchor: anchor) }
}

private struct LoopingSymbol: ViewModifier {
    let active: Bool
    let iterate: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        if iterate {
            content.symbolEffect(.variableColor.iterative, options: .repeating, isActive: active && !reduce)
        } else {
            content.symbolEffect(.pulse, options: .repeating, isActive: active && !reduce)
        }
    }
}

private struct ReducedAnimation<V: Equatable>: ViewModifier {
    let animation: Animation?
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View { content.animation(reduce ? nil : animation, value: value) }
}

// Right-to-left readiness.
extension View {
    /// ← and → as "previous" and "next". In a right-to-left layout the right arrow goes back, so the steps swap.
    public func coreSideKeys(_ step: @escaping (Int) -> KeyPress.Result) -> some View { modifier(SideKeys(step: step)) }
}

private struct SideKeys: ViewModifier {
    let step: (Int) -> KeyPress.Result
    @Environment(\.layoutDirection) private var direction
    func body(content: Content) -> some View {
        let flip = direction == .rightToLeft ? -1 : 1
        content
            .onKeyPress(.leftArrow) { step(-flip) }
            .onKeyPress(.rightArrow) { step(flip) }
    }
}

/// The two arrow keys as a hint reads them: "← →" on a left-to-right line, reversed in the text so they still sit in
/// keyboard order on a right-to-left line.
public func coreArrowKeys() -> String {
    Locale.current.language.characterDirection == .rightToLeft ? "→ ←" : "← →"
}
