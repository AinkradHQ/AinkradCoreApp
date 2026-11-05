import AppKit
import SwiftTerm
import SwiftUI

/// The SwiftTerm view for one terminal, and the only place that touches it. Bytes arrive already decoded and in frames of at
/// most 32 KiB (the runner coalesces), one frame per main-actor turn; the emulator draws into AppKit views while it parses, so
/// it has to run on the main actor (SwiftTerm's note that `feed` may run elsewhere does not hold: it crashed on a cursor view).
@MainActor
final class TerminalSurface: NSObject, TerminalViewDelegate {
    /// What the pane lays out.
    let container = SurfaceContainer()
    private let term: TerminalView
    /// Typed or pasted bytes.
    var onInput: ((Data) -> Void)?
    /// The window now fits this many columns and rows (only while the surface fills its pane).
    var onFit: ((_ cols: Int, _ rows: Int) -> Void)?
    var onBell: (() -> Void)?

    override init() {
        term = TerminalView(frame: .init(x: 0, y: 0, width: 640, height: 400))
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

    /// Draws `data`; `repaint` clears the screen first (a snapshot).
    func feed(_ data: Data, repaint: Bool = false) {
        if repaint { term.feed(text: "\u{1b}c") }
        term.feed(byteArray: [UInt8](data)[...])
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
    nonisolated func scrolled(source: TerminalView, position: Double) {
        MainActor.assumeIsolated { container.showThumb() }
    }
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

    /// The terminal's own grey scroller is hidden and its reserved strip pushed past the right edge, so the screen has
    /// the same margin on every side; a thin glass thumb stands in for it, fading in while the output scrolls
    /// (Ahmed, 2026-11-05).
    private let thumb = CALayer()
    private var fade: DispatchWorkItem?

    override func layout() {
        super.layout()
        guard let term else { return }
        let strip = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        for case let s as NSScroller in term.subviews { s.isHidden = true }
        switch mode {
        case .fill:
            layer?.backgroundColor = nil
            term.frame = CGRect(x: 0, y: 0, width: bounds.width + strip, height: bounds.height)
        case .letterbox:
            layer?.backgroundColor = NSColor(red: 2 / 255, green: 6 / 255, blue: 12 / 255, alpha: 0.92).cgColor
            let want = term.getOptimalFrameSize().size
            term.frame = CGRect(
                x: 0, y: 0, width: min(want.width, bounds.width + strip), height: min(want.height, bounds.height))
        }
        placeThumb()
    }

    private func placeThumb() {
        guard let term, let layer else { return }
        if thumb.superlayer == nil {
            thumb.backgroundColor = NSColor.white.withAlphaComponent(0.42).cgColor
            thumb.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
            thumb.borderWidth = 0.5
            thumb.cornerRadius = 2.5
            thumb.opacity = 0
            layer.addSublayer(thumb)
        }
        let size = max(0.05, min(1, term.scrollThumbsize))
        let height = max(28, bounds.height * size)
        let y = (bounds.height - height) * CGFloat(term.scrollPosition)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        thumb.frame = CGRect(x: bounds.width - 8, y: y, width: 5, height: height)
        CATransaction.commit()
        thumb.isHidden = !term.canScroll
    }

    func showThumb() {
        placeThumb()
        thumb.opacity = 1
        fade?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.thumb.opacity = 0 }
        fade = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .textArea }
    override func accessibilityLabel() -> String? { "Terminal screen" }
    override func accessibilityIdentifier() -> String { "Terminal screen" }
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
