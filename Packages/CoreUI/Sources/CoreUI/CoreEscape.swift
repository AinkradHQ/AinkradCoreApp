import AppKit
import SwiftUI

/// The one Esc owner. Anything that closes on Esc (dropdowns, confirm cards, the launcher, overlays, dialogs) registers a closer
/// while it is up; one local key monitor hands Esc to the newest closer first. A closer returns false when it has nothing to
/// close, and the next one down is asked; when none handles it the key travels on to the pane's own `onKeyPress` back handler.
@MainActor
public final class CoreEscape {
    public static let shared = CoreEscape()
    public typealias Closer = @MainActor () -> Bool

    private var stack: [(id: Int, close: Closer)] = []
    private var next = 0
    private var monitor: Any?

    public init() {}

    public var depth: Int { stack.count }

    /// Registers a closer on top of the stack and returns the id to `remove` it with.
    @discardableResult
    public func push(_ close: @escaping Closer) -> Int {
        next += 1
        stack.append((next, close))
        install()
        return next
    }

    public func remove(_ id: Int) { stack.removeAll { $0.id == id } }

    /// Asks the closers newest first. True when one of them handled the key.
    @discardableResult
    public func handle() -> Bool {
        for entry in stack.reversed() where entry.close() { return true }
        return false
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] e in
            guard e.keyCode == 53, e.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return e }
            // IME composition owns Esc until it is done.
            if let text = e.window?.firstResponder as? NSTextView, text.hasMarkedText() { return e }
            return MainActor.assumeIsolated { handle() } ? nil : e
        }
    }
}

private struct EscapeCloser: ViewModifier {
    let active: Bool
    let close: CoreEscape.Closer
    @State private var token = Token()

    final class Token { var id: Int? }

    func body(content: Content) -> some View {
        content
            .onAppear { sync() }
            .onDisappear { drop() }
            .onChange(of: active) { sync() }
    }

    private func sync() {
        if active, token.id == nil { token.id = CoreEscape.shared.push(close) } else if !active { drop() }
    }

    private func drop() {
        if let id = token.id { CoreEscape.shared.remove(id) }
        token.id = nil
    }
}

extension View {
    /// Esc runs `close` while this view is on screen (and `active`), above everything registered before it.
    public func coreEscape(active: Bool = true, _ close: @escaping CoreEscape.Closer) -> some View {
        modifier(EscapeCloser(active: active, close: close))
    }
}
