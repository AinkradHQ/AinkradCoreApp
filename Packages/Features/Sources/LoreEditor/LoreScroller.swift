import AppKit

/// The editor's scroller: no track, a thin dark glass thumb (a blurred backdrop under a dark tint) instead of the system's
/// grey one. Always the overlay style, so it floats over the page and fades out when scrolling stops.
final class LoreScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    private let glass: NSVisualEffectView = {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .withinWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = 4
        v.layer?.masksToBounds = true
        v.isHidden = true
        return v
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollerStyle = .overlay
        wantsLayer = true
        addSubview(glass)
    }

    required init?(coder: NSCoder) { nil }

    // No track: the page shows through.
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let r = rect(for: .knob)
        guard r.height > 0 else {
            glass.isHidden = true
            return
        }
        // A thin bar centred in the knob area; a little wider while the pointer is over it (the system's own cue).
        let w: CGFloat = controlSize == .regular && knobProportion > 0 ? 7 : 5
        let bar = NSRect(x: r.midX - w / 2, y: r.minY + 2, width: w, height: max(r.height - 4, 16))
        glass.isHidden = false
        glass.frame = bar
        glass.layer?.cornerRadius = w / 2 > 4 ? 4 : w / 2
        // A dark tint over the blur so the thumb reads on light and dark pages alike.
        NSColor.black.withAlphaComponent(0.38).setFill()
        NSBezierPath(roundedRect: bar, xRadius: glass.layer?.cornerRadius ?? 3, yRadius: glass.layer?.cornerRadius ?? 3)
            .fill()
    }
}
