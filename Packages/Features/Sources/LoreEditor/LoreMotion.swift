// LoreMotion — the editor's few moving parts: a checkbox that ticks, the note crossfading when another one opens, a
// heading reveal that glides, and the heading the reader is in (the outline lights it). Reduce Motion keeps the fades
// and drops the movement.
import AppKit
import CoreUI
import Observation
import QuartzCore

/// The outline heading the top of the page is in (its index among the `#`–`###` headings), for the inspector.
@MainActor @Observable public final class LoreHeadingSpy {
    public internal(set) var heading: Int?
    /// Where each heading starts; nil after an edit, rebuilt on the next scroll.
    @ObservationIgnored var starts: [Int]?
    /// A heading the person picked in the outline stays lit while the page glides to it.
    @ObservationIgnored var hold = Date.distantPast
}

private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

/// A flipped view for the tick's layers, so they draw in the page's coordinates.
private final class LoreTickView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension LoreTextView {
    /// A ticked box fills and its check draws in; an unticked one (and every one under Reduce Motion) crossfades from
    /// how it looked. Drawn over the fragment's own box for a moment, then removed.
    func animateTick(_ pr: NSRange, checked: Bool) {
        guard let rect = taskBoxRect(pr) else { return }
        let v = LoreTickView(frame: rect)
        v.wantsLayer = true
        addSubview(v)
        guard let root = v.layer else { return v.removeFromSuperview() }
        let ink = LoreInk.cg
        let box = CAShapeLayer()
        box.path = Draw.rect(v.bounds, radius: 4)
        box.frame = v.bounds
        let check = CAShapeLayer()
        check.frame = v.bounds
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 3.6, y: 7.3))
        p.addLine(to: CGPoint(x: 6.1, y: 10.3))
        p.addLine(to: CGPoint(x: 10.6, y: 4))
        check.path = p
        check.strokeColor = ink.check
        check.fillColor = nil
        check.lineWidth = 1.7
        check.lineCap = .round
        check.lineJoin = .round
        root.addSublayer(box)
        root.addSublayer(check)
        let full = checked && !reduceMotion
        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { v.removeFromSuperview() } }
        if full {
            box.fillColor = ink.boxOn
            let fill = CABasicAnimation(keyPath: "fillColor")
            fill.fromValue = ink.box
            fill.duration = Motion.press
            box.add(fill, forKey: "fill")
            let pop = CASpringAnimation(keyPath: "transform.scale")
            pop.fromValue = 0.86
            pop.toValue = 1
            pop.damping = 14
            pop.stiffness = 320
            pop.duration = pop.settlingDuration
            root.add(pop, forKey: "pop")
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0
            draw.toValue = 1
            draw.beginTime = CACurrentMediaTime() + 0.06
            draw.duration = Motion.hover
            draw.fillMode = .backwards
            draw.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            check.add(draw, forKey: "draw")
            // Held to the end of the longest part.
            let hold = CABasicAnimation(keyPath: "opacity")
            hold.fromValue = 1
            hold.toValue = 1
            hold.duration = max(pop.settlingDuration, 0.06 + Motion.hover)
            root.add(hold, forKey: "hold")
        } else {
            // How it looked a moment ago, fading out over how it looks now.
            box.fillColor = checked ? ink.box : ink.boxOn
            check.isHidden = checked
            root.opacity = 0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = Motion.hover
            root.add(fade, forKey: "fade")
        }
        CATransaction.commit()
    }

    /// The task box of a paragraph in view coordinates (as `LoreFragment.drawBlock` places it).
    func taskBoxRect(_ pr: NSRange) -> CGRect? {
        guard pr.location < ts.length, let tlm = textLayoutManager, let tcm = tlm.textContentManager,
            let loc = tcm.location(tcm.documentRange.location, offsetBy: pr.location),
            let frag = tlm.textLayoutFragment(for: loc), let first = frag.textLineFragments.first
        else { return nil }
        let style = ts.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle
        let font = ts.attribute(.font, at: pr.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 15)
        let o = textContainerOrigin
        let cx = o.x + (style?.headIndent ?? 0) - 14
        let cy =
            o.y + frag.layoutFragmentFrame.minY + first.typographicBounds.minY + first.glyphOrigin.y
            - font.capHeight / 2
        return CGRect(x: cx - 7, y: cy - 7, width: 14, height: 14)
    }

    /// The top of the line at `location`, in the page's coordinates.
    func lineTop(_ location: Int) -> CGFloat? {
        guard let tlm = textLayoutManager, let tcm = tlm.textContentManager,
            let loc = tcm.location(tcm.documentRange.location, offsetBy: location)
        else { return nil }
        // The whole note, so its place is measured (not estimated) and the page is as tall as it really is.
        tlm.ensureLayout(for: tcm.documentRange)
        sizeToFit()
        guard let frag = tlm.textLayoutFragment(for: loc) else { return nil }
        return frag.layoutFragmentFrame.minY + textContainerOrigin.y
    }
}

extension LoreEditorController {
    /// The page's scroll position drives the spy (and closes what floats over the page).
    func watchScroll() {
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.textView.tools.scrolled()
                self?.updateSpy()
            }
        }
    }

    /// The last heading at or above a line under the top of the page.
    func updateSpy() {
        guard Date() >= spy.hold else { return }
        let ts = textView.ts
        if spy.starts == nil {
            spy.starts = LoreHeadingScan.starts(in: ts)
        }
        guard let starts = spy.starts, !starts.isEmpty, let tlm = textView.textLayoutManager,
            let tcm = tlm.textContentManager
        else { return set(nil) }
        let clip = scrollView.contentView.bounds
        // At the very end of the note the last heading is the one being read, even if it is low on the page.
        let atEnd = clip.maxY >= textView.frame.height - 2
        let y = max(0, clip.minY + Space.s8 * 2 - textView.textContainerOrigin.y)
        guard let frag = tlm.textLayoutFragment(for: CGPoint(x: 1, y: y)) else { return }
        let top = tcm.offset(from: tcm.documentRange.location, to: frag.rangeInElement.location)
        let index = atEnd && clip.minY > 0 ? starts.count - 1 : starts.lastIndex { $0 <= top }
        set(index ?? (starts.isEmpty ? nil : 0))
    }

    private func set(_ heading: Int?) { if spy.heading != heading { spy.heading = heading } }

    /// A new note fades in over the old one; Reduce Motion keeps the fade (it is not movement).
    func crossfade() {
        scrollView.wantsLayer = true
        let t = CATransition()
        t.type = .fade
        t.duration = Motion.hover
        t.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        scrollView.layer?.add(t, forKey: "swap")
    }

    /// Scrolls a line to near the top of the page: a short glide, or a jump under Reduce Motion.
    func glide(to location: Int) {
        guard let y = textView.lineTop(location) else {
            return textView.scrollRangeToVisible(NSRange(location: location, length: 0))
        }
        let clip = scrollView.contentView
        let most = max(0, textView.frame.height - clip.bounds.height)
        let target = NSPoint(x: clip.bounds.minX, y: min(most, max(0, y - Space.s6)))
        if reduceMotion {
            clip.scroll(to: target)
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Motion.ui + 0.08
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                clip.animator().setBoundsOrigin(target)
            }
        }
        scrollView.reflectScrolledClipView(clip)
    }
}
