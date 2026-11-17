import AppKit
import CoreText

/// Hands TextKit 2 our own layout fragment, so list markers, checkboxes, quote bars and code wells are drawn, not stored
/// as characters.
final class LoreFragmentProvider: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        LoreFragment(textElement: textElement, range: textElement.elementRange)
    }
}

final class LoreFragment: NSTextLayoutFragment {
    private var paragraph: NSAttributedString? { (textElement as? NSTextParagraph)?.attributedString }

    override var renderingSurfaceBounds: CGRect {
        let f = layoutFragmentFrame
        let w = textLayoutManager?.textContainer?.size.width ?? f.width
        return super.renderingSurfaceBounds.union(CGRect(x: -f.minX - 8, y: -12, width: w + 16, height: f.height + 24))
    }

    override func draw(at point: CGPoint, in ctx: CGContext) {
        if let s = paragraph, s.length > 0, !textLineFragments.isEmpty {
            ctx.saveGState()
            drawBlock(s, point, ctx)
            drawRuns(s, point, ctx)
            ctx.restoreGState()
        }
        super.draw(at: point, in: ctx)
    }

    // MARK: block decorations

    private func drawBlock(_ s: NSAttributedString, _ pt: CGPoint, _ ctx: CGContext) {
        guard let block = s.attribute(.loreBlock, at: 0, effectiveRange: nil) as? String, block != "p",
            let first = textLineFragments.first
        else { return }
        let ink = LoreInk.cg
        let style = s.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let indent = style?.headIndent ?? 0
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 15)
        let lines = textLineFragments.map(\.typographicBounds).reduce(CGRect.null) { $0.union($1) }
        let baseline = pt.y + first.typographicBounds.minY + first.glyphOrigin.y
        // The fragment frame starts at the paragraph indent; markers are placed from the container edge.
        let x0 = pt.x - layoutFragmentFrame.minX
        let width = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
        let level = s.attribute(.loreLevel, at: 0, effectiveRange: nil) as? Int ?? 0

        switch block {
        case "code":
            // One fragment per block (spacing included), so hug the lines plus padding.
            let r = CGRect(x: x0, y: pt.y + lines.minY - 10, width: width, height: lines.height + 16)
            Draw.fill(ctx, Draw.rect(r, radius: 8), ink.code)
        case "quote":
            let r = CGRect(x: x0 + indent - 16, y: pt.y + lines.minY - 2, width: 3, height: lines.height + 4)
            Draw.fill(ctx, Draw.rect(r, radius: 1.5), ink.faint)
        case "ul":
            let cx = x0 + indent - 13
            let cy = baseline - font.xHeight / 2
            let sizes = [CGSize(width: 5.5, height: 5.5), CGSize(width: 7, height: 2), CGSize(width: 4, height: 4)]
            let sz = sizes[level % 3]
            let r = CGRect(x: cx - sz.width / 2, y: cy - sz.height / 2, width: sz.width, height: sz.height)
            Draw.fill(ctx, Draw.rect(r, radius: 1.5), ink.text2)
        case "ol":
            let n = s.attribute(.loreOrdinal, at: 0, effectiveRange: nil) as? Int ?? 1
            Draw.text(ctx, "\(n).", font: font, color: ink.text2, rightEdge: x0 + indent - 7, baseline: baseline)
        case "task":
            let checked = s.attribute(.loreChecked, at: 0, effectiveRange: nil) as? Bool ?? false
            Draw.box(ctx, center: CGPoint(x: x0 + indent - 14, y: baseline - font.capHeight / 2), checked: checked)
        default: break
        }
    }

    // MARK: inline wells (code, note links)

    private func drawRuns(_ s: NSAttributedString, _ pt: CGPoint, _ ctx: CGContext) {
        for line in textLineFragments {
            let lr = line.characterRange
            guard lr.length > 0, NSMaxRange(lr) <= s.length else { continue }
            // One key at a time, so a run split by other attributes (kern, link) still draws as one well.
            for key in [NSAttributedString.Key.loreCode, .loreChip] {
                s.enumerateAttribute(key, in: lr) { v, r, _ in
                    guard v != nil else { return }
                    let font =
                        s.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 15)
                    let x0 = line.locationForCharacter(at: r.location).x
                    let kern = s.attribute(.kern, at: NSMaxRange(r) - 1, effectiveRange: nil) as? CGFloat ?? 0
                    let x1 = line.locationForCharacter(at: min(NSMaxRange(r), NSMaxRange(lr))).x - kern
                    let ox = pt.x + line.typographicBounds.minX
                    let base = pt.y + line.typographicBounds.minY + line.glyphOrigin.y
                    let rect = CGRect(
                        x: ox + x0 - 3, y: base - font.ascender - 1.5, width: x1 - x0 + 6,
                        height: font.ascender - font.descender + 3)
                    Draw.fill(ctx, Draw.rect(rect, radius: 4), key == .loreChip ? LoreInk.cg.chip : LoreInk.cg.code)
                }
            }
        }
    }
}

/// Small CoreGraphics helpers (rounded rects only, no outlines).
enum Draw {
    static func rect(_ r: CGRect, radius: CGFloat) -> CGPath {
        CGPath(
            roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2),
            transform: nil)
    }

    static func fill(_ ctx: CGContext, _ path: CGPath, _ color: CGColor) {
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    static func box(_ ctx: CGContext, center c: CGPoint, checked: Bool) {
        let r = CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)
        fill(ctx, rect(r, radius: 4), checked ? LoreInk.cg.boxOn : LoreInk.cg.box)
        guard checked else { return }
        ctx.setStrokeColor(LoreInk.cg.check)
        ctx.setLineWidth(1.7)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: CGPoint(x: r.minX + 3.6, y: r.midY + 0.3))
        ctx.addLine(to: CGPoint(x: r.minX + 6.1, y: r.maxY - 3.7))
        ctx.addLine(to: CGPoint(x: r.maxX - 3.4, y: r.minY + 4))
        ctx.strokePath()
    }

    static func text(
        _ ctx: CGContext, _ str: String, font: NSFont, color: CGColor, rightEdge: CGFloat, baseline: CGFloat
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: str, attributes: attrs))
        let w = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: rightEdge - w, y: baseline)
        CTLineDraw(line, ctx)
    }
}
