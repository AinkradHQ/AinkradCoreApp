import AppKit

/// Draws the predicted cells over the terminal, in the terminal's cell grid: dimmed and underlined until the real output
/// replaces them. It never takes a click and is not part of the emulator.
final class PredictionOverlay: NSView {
    var font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) { didSet { needsDisplay = true } }
    var ink = NSColor.white
    var paper = NSColor.black
    var caretColor = NSColor.white
    var caretShape = TerminalPrefs.CursorShape.block
    private var row = 0
    private var real = 0
    private var caret = 0
    private var cells: [(x: Int, ch: Character)] = []

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    /// `real` is where the emulator's own cursor still sits (covered), `caret` where the typed text now ends.
    func set(row: Int, cells: [(x: Int, ch: Character)], real: Int, caret: Int) {
        guard
            cells.map(\.x) != self.cells.map(\.x) || cells.map(\.ch) != self.cells.map(\.ch) || row != self.row
                || real != self.real || caret != self.caret
        else { return }
        self.row = row
        self.real = real
        self.caret = caret
        self.cells = cells
        isHidden = cells.isEmpty
        needsDisplay = true
    }

    /// The emulator's own cursor cell (its caret view's frame, in the terminal's coordinates): the grid is measured from it,
    /// so the predicted cells sit exactly where the real ones will, whatever the font or the emulator's own offsets.
    var caretFrame: () -> CGRect = { .zero }

    override func draw(_ dirty: NSRect) {
        let cf = caretFrame()
        guard cf.width > 0, cf.height > 0 else { return }
        let size = cf.size
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: ink.withAlphaComponent(0.7),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        func rect(_ x: Int) -> CGRect {
            // The terminal is not flipped, this view is: the caret's top edge is its height minus the caret's top.
            CGRect(
                x: cf.minX + CGFloat(x - real) * size.width, y: bounds.height - cf.maxY, width: size.width,
                height: size.height)
        }
        guard !cells.isEmpty else { return }
        // The emulator's cursor has not moved yet: cover it, then draw the cursor where the text now ends.
        paper.setFill()
        rect(real).fill()
        for (x, ch) in cells {
            let r = rect(x)
            if ch == " " {
                paper.setFill()
                r.fill()
            } else {
                NSAttributedString(string: String(ch), attributes: attrs).draw(at: r.origin)
            }
        }
        caretColor.setFill()
        let c = rect(caret)
        switch caretShape {
        case .block: c.fill()
        case .underline: CGRect(x: c.minX, y: c.maxY - 2, width: c.width, height: 2).fill()
        case .bar: CGRect(x: c.minX, y: c.minY, width: 2, height: c.height).fill()
        }
    }
}
