import AppKit
import DesignEngine
import Foundation

/// Text on the canvas (V2-04) and the drawing tools (AinkradCore #522). A double-click on a text node, or a click with the
/// text tool, opens a text session in the engine; while it is open the canvas is an `NSTextInputClient`, so typing, the
/// IME's marked text, the caret keys and word moves go to the engine. Escape ends the session.
extension Engine {
    struct TextState: Decodable {
        let id: String
        let text: String
        let selection: [Int]
        let marked: [Int]?
    }

    var textActive: Bool { de_text_active(h) == 1 }

    /// `view = doc × zoom + pan` (`de_camera`).
    struct Camera: Decodable {
        let zoom: Double
        let pan: [Double]
    }
    func camera() -> Camera? {
        guard let d = read({ de_camera(h, $0, $1, $2) }) else { return nil }
        return try? JSONDecoder().decode(Camera.self, from: d)
    }
    var tool: Int32 { max(0, de_tool(h)) }
    @discardableResult func setTool(_ t: Int32) -> Bool { de_set_tool(h, UInt32(t)) == DE_OK }

    func textState() -> TextState? {
        guard let d = read({ de_text_state(h, $0, $1, $2) }) else { return nil }
        return try? JSONDecoder().decode(TextState.self, from: d)
    }

    /// The rect (view points) of a character range, and the range the engine snapped it to.
    func textFirstRect(_ r: NSRange) -> (CGRect, NSRange)? {
        struct Out: Decodable {
            let rect: [Double]
            let range: [Int]
        }
        guard
            let d = read({ de_text_first_rect(h, Int64(r.location), Int64(r.length), $0, $1, $2) }),
            let o = try? JSONDecoder().decode(Out.self, from: d), o.rect.count == 4, o.range.count == 2
        else { return nil }
        return (
            CGRect(x: o.rect[0], y: o.rect[1], width: o.rect[2], height: o.rect[3]),
            NSRange(location: o.range[0], length: o.range[1])
        )
    }
}

extension DesignCanvasNSView: @preconcurrency NSTextInputClient {
    // MARK: tools

    /// The current tool (`DE_TOOL_*`).
    public var editorTool: Int { Int(engine.tool) }

    /// Picks a tool; ends a text edit first. The cursor and the chrome follow.
    public func editorSetTool(_ t: Int) {
        if engine.textActive { de_text_end(engine.h) }
        engine.setTool(Int32(t))
        textChanged()
    }

    /// The single-letter tool keys, as Figma has them (only while no text is being edited).
    static func toolKey(_ c: String) -> Int32? {
        switch c {
        case "v": DE_TOOL_SELECT
        case "h": DE_TOOL_HAND
        case "f", "#": DE_TOOL_FRAME
        case "r": DE_TOOL_RECT
        case "o": DE_TOOL_ELLIPSE
        case "l": DE_TOOL_LINE
        case "t": DE_TOOL_TEXT
        case "p": DE_TOOL_PEN
        default: nil
        }
    }

    func textChanged() {
        loop.wake(input: true)
        sync?.flush()
        onChange?()
    }

    // MARK: NSTextInputClient

    private static func string(_ s: Any) -> String {
        (s as? NSAttributedString)?.string ?? (s as? String) ?? ""
    }
    private static func loc(_ r: NSRange) -> Int64 {
        r.location == NSNotFound ? Int64(DE_TEXT_NO_RANGE) : Int64(r.location)
    }

    public func insertText(_ string: Any, replacementRange: NSRange) {
        let b = Array(Self.string(string).utf8)
        de_text_insert(engine.h, b, b.count, Self.loc(replacementRange), Int64(replacementRange.length))
        textChanged()
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let b = Array(Self.string(string).utf8)
        de_text_set_marked(
            engine.h, b, b.count, Int64(selectedRange.location), Int64(selectedRange.length),
            Self.loc(replacementRange),
            Int64(replacementRange.length))
        textChanged()
    }

    public func unmarkText() {
        de_text_unmark(engine.h)
        textChanged()
    }

    public func selectedRange() -> NSRange {
        guard let s = engine.textState(), s.selection.count == 2 else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: s.selection[0], length: s.selection[1])
    }

    public func markedRange() -> NSRange {
        guard let m = engine.textState()?.marked, m.count == 2 else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: m[0], length: m[1])
    }

    public func hasMarkedText() -> Bool { engine.textState()?.marked != nil }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?)
        -> NSAttributedString?
    {
        guard let text = engine.textState()?.text else { return nil }
        let ns = text as NSString
        let r = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        actualRange?.pointee = r
        return NSAttributedString(string: ns.substring(with: r))
    }

    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let (rect, snapped) = engine.textFirstRect(range), let window else { return .zero }
        actualRange?.pointee = snapped
        return window.convertToScreen(convert(rect, to: nil))
    }

    public func characterIndex(for point: NSPoint) -> Int {
        guard let window else { return NSNotFound }
        let p = convert(window.convertPoint(fromScreen: point), from: nil)
        let i = de_text_index_at(engine.h, Float(p.x), Float(p.y))
        return i >= 0 ? Int(i) : NSNotFound
    }

    /// The editing keys, as AppKit names them.
    public override func doCommand(by selector: Selector) {
        let shift = UInt32(DE_MOD_SHIFT)
        let option = UInt32(DE_MOD_OPTION)
        let command = UInt32(DE_MOD_COMMAND)
        let map: [String: (Int32, UInt32)] = [
            "moveLeft:": (DE_TEXT_LEFT, 0), "moveRight:": (DE_TEXT_RIGHT, 0), "moveUp:": (DE_TEXT_UP, 0),
            "moveDown:": (DE_TEXT_DOWN, 0),
            "moveLeftAndModifySelection:": (DE_TEXT_LEFT, shift),
            "moveRightAndModifySelection:": (DE_TEXT_RIGHT, shift),
            "moveUpAndModifySelection:": (DE_TEXT_UP, shift), "moveDownAndModifySelection:": (DE_TEXT_DOWN, shift),
            "moveWordLeft:": (DE_TEXT_LEFT, option), "moveWordRight:": (DE_TEXT_RIGHT, option),
            "moveWordLeftAndModifySelection:": (DE_TEXT_LEFT, option | shift),
            "moveWordRightAndModifySelection:": (DE_TEXT_RIGHT, option | shift),
            "moveToBeginningOfLine:": (DE_TEXT_LEFT, command), "moveToEndOfLine:": (DE_TEXT_RIGHT, command),
            "moveToLeftEndOfLine:": (DE_TEXT_LEFT, command), "moveToRightEndOfLine:": (DE_TEXT_RIGHT, command),
            "moveToBeginningOfDocument:": (DE_TEXT_UP, command), "moveToEndOfDocument:": (DE_TEXT_DOWN, command),
            "deleteBackward:": (DE_TEXT_DELETE_BACK, 0), "deleteForward:": (DE_TEXT_DELETE_FORWARD, 0),
            "deleteWordBackward:": (DE_TEXT_DELETE_BACK, option),
            "deleteWordForward:": (DE_TEXT_DELETE_FORWARD, option),
            "deleteToBeginningOfLine:": (DE_TEXT_DELETE_BACK, command), "selectAll:": (DE_TEXT_SELECT_ALL, 0),
            "insertNewline:": (DE_TEXT_NEWLINE, 0), "insertLineBreak:": (DE_TEXT_NEWLINE, 0),
        ]
        if NSStringFromSelector(selector) == "cancelOperation:" {
            de_text_end(engine.h)
        } else if let (cmd, mods) = map[NSStringFromSelector(selector)] {
            de_text_command(engine.h, UInt32(cmd), mods)
        } else {
            return
        }
        textChanged()
    }
}
