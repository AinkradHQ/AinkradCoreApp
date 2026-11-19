import AppKit
import CoreUI
import SwiftUI

/// Sideways swipes anywhere over the workspace move the strip (the terminal panes eat scroll events, so the window's
/// events are watched while the strip can scroll). Vertical scrolling is left to the panes.
struct StripSwipe: NSViewRepresentable {
    let enabled: Bool
    let moved: (CGFloat) -> Void
    let ended: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.view = v
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.moved = moved
        context.coordinator.ended = ended
        context.coordinator.listen()
    }

    static func dismantleNSView(_ v: NSView, coordinator: Coordinator) { coordinator.stop() }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        weak var view: NSView?
        var enabled = false
        var moved: (CGFloat) -> Void = { _ in }
        var ended: () -> Void = {}
        private var monitor: Any?

        func listen() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                guard let self, self.enabled, let v = self.view, e.window === v.window else { return e }
                let p = v.convert(e.locationInWindow, from: nil)
                guard v.bounds.contains(p), abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) else {
                    if e.phase == .ended || e.momentumPhase == .ended { self.ended() }
                    return e
                }
                self.moved(e.hasPreciseScrollingDeltas ? e.scrollingDeltaX : e.scrollingDeltaX * 12)
                if e.phase == .ended || e.momentumPhase == .ended { self.ended() }
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

/// Where the strip is: a thin glass bar along the bottom edge.
struct StripBar: View {
    let offset: CGFloat
    let visible: CGFloat
    let total: CGFloat
    var body: some View {
        GeometryReader { g in
            let w = max(48, g.size.width * visible / max(total, 1))
            let x = (g.size.width - w) * offset / max(total - visible, 1)
            coreShape(2).fill(GlassInk.primary.opacity(0.45)).frame(width: w, height: 4).offset(x: x)
        }
        .frame(height: 4)
        .padding(.horizontal, Space.s4).padding(.bottom, 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
