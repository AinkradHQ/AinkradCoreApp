import AppKit
import SwiftTerm
import SwiftUI
import TerminalFeed

/// The SwiftTerm view for one terminal, and the only place that touches it. Output is fed through `TerminalFeeder`, a serial
/// background queue, so the main actor does view updates and nothing else.
@MainActor
final class TerminalSurface: NSObject, TerminalViewDelegate {
    /// What the pane lays out.
    let container = SurfaceContainer()
    private let term: TerminalView
    private let feeder: TerminalFeeder
    /// Typed or pasted bytes.
    var onInput: ((Data) -> Void)?
    /// The window now fits this many columns and rows (only while the surface fills its pane).
    var onFit: ((_ cols: Int, _ rows: Int) -> Void)?
    var onBell: (() -> Void)?

    override init() {
        term = TerminalView(frame: .init(x: 0, y: 0, width: 640, height: 400))
        feeder = TerminalFeeder(view: term)
        super.init()
        term.terminalDelegate = self
        term.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        // The prototype's terminal: deep blue glass with cool text, the same in night and day.
        term.nativeBackgroundColor = NSColor(red: 3 / 255, green: 8 / 255, blue: 16 / 255, alpha: 0.78)
        term.nativeForegroundColor = NSColor(red: 0xCF / 255, green: 0xE0 / 255, blue: 0xF5 / 255, alpha: 1)
        term.caretColor = NSColor(red: 0x7F / 255, green: 0xB8 / 255, blue: 0xFF / 255, alpha: 1)
        term.optionAsMetaKey = true
        // Reduce Motion: the cursor does not blink.
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        term.getTerminal().setCursorStyle(still ? .steadyBlock : .blinkBlock)
        container.addSubview(term)
        container.term = term
        container.surface = self
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
    }

    // MARK: output

    /// Draws `data`. `drawn` runs on the feed queue once SwiftTerm has taken it (credit goes back from there).
    func feed(_ data: Data, repaint: Bool = false, drawn: @escaping @Sendable (Int) -> Void) {
        let n = data.count
        feeder.feed(data, reset: repaint) { drawn(n) }
    }

    /// The last of what is on screen and in the scrollback, as text: for VoiceOver and the live test.
    func visibleText(limit: Int = 4096) -> String {
        let data = term.getTerminal().getBufferAsData()
        return String(decoding: data.suffix(limit), as: UTF8.self)
    }

    // MARK: size

    var size: (cols: Int, rows: Int) { (term.getTerminal().cols, term.getTerminal().rows) }

    /// Fill the pane (this window sizes the terminal) or show the terminal at `cols`×`rows` inside it, letterboxed.
    func layoutMode(_ mode: SurfaceContainer.Mode) {
        if case .letterbox(let c, let r) = mode, size != (c, r) { term.resize(cols: c, rows: r) }
        container.mode = mode
        container.needsLayout = true
    }

    func focus() { container.window?.makeFirstResponder(term) }

    // MARK: TerminalViewDelegate (called on the main thread)

    nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        MainActor.assumeIsolated { if container.mode == .fill { onFit?(newCols, newRows) } }
    }
    nonisolated func setTerminalTitle(source: TerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let bytes = Data(data)
        MainActor.assumeIsolated { onInput?(bytes) }
    }
    nonisolated func scrolled(source: TerminalView, position: Double) {}
    nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased()) {
            NSWorkspace.shared.open(url)
        }
    }
    nonisolated func bell(source: TerminalView) { MainActor.assumeIsolated { onBell?() } }
    nonisolated func clipboardCopy(source: TerminalView, content: Data) {
        MainActor.assumeIsolated {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(content, forType: .string)
        }
    }
    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

/// Lays the terminal out: filling, or at the terminal's own size in the corner. Flipped, so the top-left is the origin.
final class SurfaceContainer: NSView {
    enum Mode: Equatable {
        case fill
        case letterbox(cols: Int, rows: Int)
    }
    var mode: Mode = .fill
    weak var term: TerminalView?
    weak var surface: TerminalSurface?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func layout() {
        super.layout()
        guard let term else { return }
        switch mode {
        case .fill:
            layer?.backgroundColor = nil
            term.frame = bounds
        case .letterbox:
            layer?.backgroundColor = NSColor(red: 2 / 255, green: 6 / 255, blue: 12 / 255, alpha: 0.92).cgColor
            let want = term.getOptimalFrameSize().size
            term.frame = CGRect(
                x: 0, y: 0, width: min(want.width, bounds.width), height: min(want.height, bounds.height))
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .textArea }
    override func accessibilityLabel() -> String? { "Terminal screen" }
    override func accessibilityValue() -> Any? {
        let text: String? = MainActor.assumeIsolated { surface?.visibleText() }
        return text
    }
}

/// The pane's terminal area: the surface's container, dimmed when it shows an old or finished screen.
struct TerminalScreen: NSViewRepresentable {
    let surface: TerminalSurface
    func makeNSView(context: Context) -> SurfaceContainer { surface.container }
    func updateNSView(_ nsView: SurfaceContainer, context: Context) {}
}
