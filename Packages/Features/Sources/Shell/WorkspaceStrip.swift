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
            coreShape(2).fill(.white.opacity(0.45)).frame(width: w, height: 4).offset(x: x)
        }
        .frame(height: 4)
        .padding(.horizontal, Space.s4).padding(.bottom, 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Auto-stack (Ahmed, 2026-11-05: no scrolling to reach an app). When the apps do not fit side by side at their minimum
/// width, the first ones keep their columns and the rest share the last column as a stack: the active one is on top,
/// the others wait behind it (their tabs stay in the top bar; ⌃Tab or a click brings one forward).
struct Stack {
    var layout: TileLayout
    var members: [String] = []
    var front: String?
    var hidden: Set<String> = []
    var slot: CGRect?

    static func make(
        order: [String], tiled: TileLayout, area: CGSize, minWidth: CGFloat, active: String?, front: String?,
        focused: Bool
    ) -> Stack {
        let gap = ShellMetrics.paneGap
        let cap = max(1, Int((area.width + gap) / (minWidth + gap)))
        guard !focused, tiled.isStrip, order.count > cap else { return Stack(layout: tiled) }
        let lead = Array(order.prefix(cap - 1))
        let members = Array(order.dropFirst(cap - 1))
        let top =
            active.flatMap { members.contains($0) ? $0 : nil } ?? front.flatMap { members.contains($0) ? $0 : nil }
            ?? members[0]
        let w = (area.width - gap * CGFloat(cap - 1)) / CGFloat(cap)
        var out = TileLayout(contentWidth: area.width, isStrip: false)
        for (i, id) in lead.enumerated() {
            out.frames[id] = CGRect(x: CGFloat(i) * (w + gap), y: 0, width: w, height: area.height)
        }
        let slot = CGRect(x: CGFloat(cap - 1) * (w + gap), y: 0, width: w, height: area.height)
        for id in members { out.frames[id] = slot }
        return Stack(
            layout: out, members: members, front: top, hidden: Set(members.filter { $0 != top }), slot: slot)
    }
}

/// The cards waiting behind the stack's top pane, peeking out above it.
struct StackBehind: View {
    let slot: CGRect
    let count: Int
    var body: some View {
        ZStack(alignment: .top) {
            ForEach(0..<min(count, 2), id: \.self) { i in
                coreShape(Radius.pane).fill(.white.opacity(0.06 - Double(i) * 0.02))
                    .overlay { coreShape(Radius.pane).strokeBorder(.white.opacity(0.14), lineWidth: 1) }
                    .padding(.horizontal, CGFloat(i + 1) * 10)
                    .offset(y: -CGFloat(i + 1) * 5)
            }
        }
        .frame(width: slot.width, height: slot.height)
        .offset(x: slot.minX, y: slot.minY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// "2 of 3" on the stack, with the key that cycles it.
struct StackBadge: View {
    let index: Int
    let count: Int
    let slot: CGRect
    var body: some View {
        HStack(spacing: Space.s1) {
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 10, weight: .semibold))
            Text("\(index) of \(count)").monospacedDigit().contentTransition(.numericText())
            Text("⌃Tab").coreFont(size: 10, weight: .medium, design: .rounded).opacity(0.7)
        }
        .coreFont(size: MacTextSize.meta, weight: .semibold)
        .foregroundStyle(.white)
        .padding(.horizontal, Space.s2).frame(height: 22)
        .background(.black.opacity(0.45), in: coreShape(6))
        .overlay { coreShape(6).strokeBorder(.white.opacity(0.2), lineWidth: 1) }
        .padding(Space.s2)
        .frame(width: slot.width, height: slot.height, alignment: .bottomTrailing)
        .offset(x: slot.minX, y: slot.minY)
        .allowsHitTesting(false)
        .animation(.spring(duration: 0.3), value: index)
    }
}
