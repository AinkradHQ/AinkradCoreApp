import AppKit

/// Draws the predicted cells over the terminal, in the terminal's cell grid: dimmed and underlined until the real output
/// replaces them. It never takes a click and is not part of the emulator.
final class PredictionOverlay: NSView {
    var font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) { didSet { needsDisplay = true } }
    var ink = NSColor.white
    var paper = NSColor.black
    private var row = 0
    private var cells: [(x: Int, ch: Character)] = []

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    func set(row: Int, cells: [(x: Int, ch: Character)]) {
        guard cells.map(\.x) != self.cells.map(\.x) || cells.map(\.ch) != self.cells.map(\.ch) || row != self.row else {
            return
        }
        self.row = row
        self.cells = cells
        isHidden = cells.isEmpty
        needsDisplay = true
    }

    /// The emulator's own cell size: the advance of "W" by line height (ascent + descent + leading, rounded up).
    private var cell: CGSize {
        let w = font.advancement(forGlyph: font.glyph(withName: "W")).width
        return CGSize(width: w, height: ceil(font.ascender - font.descender + font.leading))
    }

    override func draw(_ dirty: NSRect) {
        let size = cell
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: ink.withAlphaComponent(0.7),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        for (x, ch) in cells {
            let origin = CGPoint(x: CGFloat(x) * size.width, y: CGFloat(row) * size.height)
            let r = CGRect(origin: origin, size: size)
            if ch == " " {
                // An erased character: cover the old glyph until the real output removes it.
                paper.setFill()
                r.fill()
            } else {
                NSAttributedString(string: String(ch), attributes: attrs).draw(at: r.origin)
            }
        }
    }
}
