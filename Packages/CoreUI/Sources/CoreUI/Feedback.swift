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
}
