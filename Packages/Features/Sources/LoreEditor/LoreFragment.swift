import AppKit
import CoreText
import CoreUI

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
            let grid = tableRows(s)
            drawBlock(s, point, ctx, well: grid == nil)
            if let grid {
                drawGrid(grid, point, ctx)
            } else {
                drawRuns(s, point, ctx)
            }
            ctx.restoreGState()
            if grid != nil { return }
        }
        super.draw(at: point, in: ctx)
    }

    // MARK: block decorations

    private func drawBlock(_ s: NSAttributedString, _ pt: CGPoint, _ ctx: CGContext, well: Bool = true) {
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
            guard well else { break }
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

    // MARK: tables

    /// The table's lines when it is drawn as a grid: a table block with the caret elsewhere. With the caret inside it
    /// stays text, so every edit is plain typing.
    private func tableRows(_ s: NSAttributedString) -> [String]? {
        guard s.attribute(.loreTable, at: 0, effectiveRange: nil) != nil, !caretInside else { return nil }
        let lines = s.string.trimmingCharacters(in: .newlines).components(separatedBy: "\u{2028}")
        guard lines.count >= 2, textLineFragments.count >= lines.count - 1, GFMTable.isSeparator(lines[1]) else {
            return nil
        }
        return lines
    }

    private var caretInside: Bool {
        guard let tlm = textLayoutManager, let er = textElement?.elementRange else { return false }
        return tlm.textSelections.contains { sel in
            sel.textRanges.contains { $0.isEmpty ? er.contains($0.location) : $0.intersects(er) }
        }
    }

    /// One rounded well per cell (6 pt, 3 pt gaps), header lifted and semibold, columns aligned as the separator says.
    /// The separator line is not drawn, so the rows close up and the spare line sits below the grid.
    private func drawGrid(_ lines: [String], _ pt: CGPoint, _ ctx: CGContext) {
        let aligns = GFMTable.alignments(lines[1])
        let rows = ([lines[0]] + lines.dropFirst(2)).map { GFMTable.cells($0) }
        let cols = rows.map(\.count).max() ?? 0
        guard cols > 0 else { return }
        let cells = MainActor.assumeIsolated {
            Cells(
                rows: rows.enumerated().map { r, row in
                    (0..<cols).map { c in
                        Self.cellText(c < row.count ? row[c] : "", header: r == 0, align: aligns[safe: c])
                    }
                }
            )
        }.rows
        let pad: CGFloat = 12
        let gap: CGFloat = 3
        let avail =
            (textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width) - gap * CGFloat(cols - 1)
        var w = (0..<cols).map { c in (cells.map { ceil($0[c].size().width) }.max() ?? 0) + pad * 2 }
        let total = w.reduce(0, +)
        // Narrower than the page: spread the spare room. Wider: shrink every column alike; long cells end in "…".
        w = w.map { $0 * avail / total }
        let x0 = pt.x - layoutFragmentFrame.minX
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        defer { NSGraphicsContext.restoreGraphicsState() }
        for (r, row) in cells.enumerated() {
            let line = textLineFragments[r].typographicBounds
            let next = r + 1 < textLineFragments.count ? textLineFragments[r + 1].typographicBounds.minY : line.maxY
            let h = max(next - line.minY - gap, 24)
            var x = x0
            for (c, text) in row.enumerated() {
                let cell = CGRect(x: x, y: pt.y + line.minY, width: w[c], height: h)
                Draw.fill(ctx, Draw.rect(cell, radius: 6), LoreInk.cg.chip)
                if r == 0 { Draw.fill(ctx, Draw.rect(cell, radius: 6), LoreInk.cg.head) }
                let th = ceil(text.size().height)
                text.draw(
                    with: CGRect(
                        x: cell.minX + pad, y: cell.midY - th / 2, width: max(0, cell.width - pad * 2), height: th),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
                x += w[c] + gap
            }
        }
    }

    /// A cell's inline Markdown (bold, italic, code, links) as drawable text.
    @MainActor private static func cellText(_ md: String, header: Bool, align: GFMTable.Align?) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: MarkdownReader.inline(md))
        let size = MacTextSize.scaled(header ? 12.5 : 13.5)
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byTruncatingTail
        p.alignment = align == .center ? .center : align == .trailing ? .right : .left
        out.enumerateAttributes(in: NSRange(location: 0, length: out.length)) { a, r, _ in
            let font: NSFont =
                a[.loreCode] != nil
                ? Typeface.mono(size - 1)
                : Typeface.text(
                    size, header || a[.loreBold] != nil ? .semibold : .regular, italic: a[.loreItalic] != nil)
            out.setAttributes(
                [
                    .font: font, .foregroundColor: header ? LoreInk.text2 : LoreInk.text, .paragraphStyle: p,
                    .underlineStyle: a[.link] != nil ? NSUnderlineStyle.single.rawValue : 0,
                ], range: r)
        }
        return out
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

/// Drawn text carried out of `assumeIsolated` (drawing is on the main thread; `NSAttributedString` is not `Sendable`).
private struct Cells: @unchecked Sendable { let rows: [[NSAttributedString]] }

extension Array {
    fileprivate subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
