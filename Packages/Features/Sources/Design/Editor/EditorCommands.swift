import AppKit
import CoreUI
import Foundation
import SwiftUI

/// A key press as the editor sees it: the layout-independent letter (`chars`), the key code, and the modifiers. A plain
/// value, so the key map is tested without an event.
public struct EditorKey: Sendable, Equatable {
    public var chars: String
    public var keyCode: UInt16
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    public init(
        chars: String, keyCode: UInt16, command: Bool = false, shift: Bool = false, option: Bool = false,
        control: Bool = false
    ) {
        self.chars = chars.lowercased()
        self.keyCode = keyCode
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    public init(_ e: NSEvent) {
        let f = e.modifierFlags
        self.init(
            chars: e.charactersIgnoringModifiers ?? "", keyCode: e.keyCode, command: f.contains(.command),
            shift: f.contains(.shift), option: f.contains(.option), control: f.contains(.control))
    }
}

/// What the keyboard (and the menus) can ask of the editor, with the keys Figma uses.
enum EditorCommand: CaseIterable {
    case copy, cut, paste, duplicate
    case group, ungroup, bringForward, sendBackward, bringToFront, sendToBack
    case selectAll, selectChildren, selectParent
    case createComponent, detachInstance
    case zoomIn, zoomOut, zoom100, fitAll, fitSelection
    case autoLayout, toggleHidden, toggleLock, renameLayer, shortcuts

    var title: String {
        switch self {
        case .copy: "Copy"
        case .cut: "Cut"
        case .paste: "Paste"
        case .duplicate: "Duplicate"
        case .group: "Group selection"
        case .ungroup: "Ungroup"
        case .bringForward: "Bring forward"
        case .sendBackward: "Send backward"
        case .bringToFront: "Bring to front"
        case .sendToBack: "Send to back"
        case .selectAll: "Select all"
        case .selectChildren: "Select what is inside"
        case .selectParent: "Select the parent"
        case .createComponent: "Create component"
        case .detachInstance: "Detach instance"
        case .zoomIn: "Zoom in"
        case .zoomOut: "Zoom out"
        case .zoom100: "Zoom to 100%"
        case .fitAll: "Zoom to fit everything"
        case .fitSelection: "Zoom to the selection"
        case .autoLayout: "Add auto layout"
        case .toggleHidden: "Hide or show"
        case .toggleLock: "Lock or unlock"
        case .renameLayer: "Rename the layer"
        case .shortcuts: "Show these shortcuts"
        }
    }

    /// The keys, as Mac menus write them.
    var keys: String {
        switch self {
        case .copy: "⌘C"
        case .cut: "⌘X"
        case .paste: "⌘V"
        case .duplicate: "⌘D"
        case .group: "⌘G"
        case .ungroup: "⇧⌘G"
        case .bringForward: "⌘]"
        case .sendBackward: "⌘["
        case .bringToFront: "⌥⌘]"
        case .sendToBack: "⌥⌘["
        case .selectAll: "⌘A"
        case .selectChildren: "⏎"
        case .selectParent: "⇧⏎"
        case .createComponent: "⌥⌘K"
        case .detachInstance: "⌥⌘B"
        case .zoomIn: "⌘="
        case .zoomOut: "⌘-"
        case .zoom100: "⌘0"
        case .fitAll: "⇧1"
        case .fitSelection: "⇧2"
        case .autoLayout: "⇧A"
        case .toggleHidden: "⇧⌘H"
        case .toggleLock: "⇧⌘L"
        case .renameLayer: "⌘R"
        case .shortcuts: "?"
        }
    }

    /// The key map. `nil`: not an editor command (the engine or the tool letters take it). Control never takes part.
    static func from(_ k: EditorKey) -> EditorCommand? {
        guard !k.control else { return nil }
        let c = k.chars
        if k.command {
            switch (c, k.shift, k.option) {
            case ("c", false, false): return .copy
            case ("x", false, false): return .cut
            case ("v", false, false): return .paste
            case ("d", false, false): return .duplicate
            case ("a", false, false): return .selectAll
            case ("g", false, false): return .group
            case ("g", true, false): return .ungroup
            case ("h", true, false): return .toggleHidden
            case ("l", true, false): return .toggleLock
            case ("r", false, false): return .renameLayer
            case ("k", false, true): return .createComponent
            case ("b", false, true): return .detachInstance
            default: break
            }
            switch (k.keyCode, k.shift, k.option) {
            case (30, false, false): return .bringForward  // ]
            case (33, false, false): return .sendBackward  // [
            case (30, false, true): return .bringToFront
            case (33, false, true): return .sendToBack
            case (24, _, false): return .zoomIn  // = (and + with Shift)
            case (27, false, false): return .zoomOut  // -
            case (29, false, false): return .zoom100  // 0
            case (18, false, false): return .fitSelection  // ⌘1, as before
            default: return nil
            }
        }
        if k.option { return nil }
        switch (k.keyCode, k.shift) {
        case (18, true): return .fitAll  // ⇧1
        case (19, true): return .fitSelection  // ⇧2
        case (29, true): return .zoom100  // ⇧0
        case (36, false), (76, false): return .selectChildren
        case (36, true), (76, true): return .selectParent
        case (42, false): return .selectParent  // \
        case (44, true): return .shortcuts  // ?
        default: break
        }
        if c == "a", k.shift { return .autoLayout }
        return nil
    }
}

/// The keyboard sheet's content: every key the editor answers, grouped.
enum ShortcutList {
    struct Group: Identifiable {
        var id: String { title }
        let title: String
        let rows: [(words: String, keys: String)]
    }

    static func commands(_ list: [EditorCommand]) -> [(words: String, keys: String)] {
        list.map { ($0.title, $0.keys) }
    }

    static let groups: [Group] = [
        Group(
            title: "Tools",
            rows: [
                ("Move", "V"), ("Hand", "H"), ("Frame", "F"), ("Rectangle", "R"), ("Ellipse", "O"), ("Line", "L"),
                ("Text", "T"), ("Pen", "P"), ("Pan with any tool", "Space + drag"),
            ]),
        Group(
            title: "Edit",
            rows: commands([.copy, .cut, .paste, .duplicate, .selectAll, .renameLayer])
                + [("Undo", "⌘Z"), ("Redo", "⇧⌘Z"), ("Copy while dragging", "⌥ + drag"), ("Delete", "⌫")]),
        Group(
            title: "Arrange",
            rows: commands([
                .group, .ungroup, .bringForward, .sendBackward, .bringToFront, .sendToBack, .autoLayout,
                .toggleHidden, .toggleLock,
            ])),
        Group(
            title: "Components",
            rows: commands([.createComponent, .detachInstance])),
        Group(
            title: "Select",
            rows: commands([.selectChildren, .selectParent]) + [("Select nothing", "Esc"), ("Nudge", "Arrows")]),
        Group(
            title: "View",
            rows: commands([.zoomIn, .zoomOut, .zoom100, .fitAll, .fitSelection]) + [
                ("Zoom with the mouse", "⌘ + scroll"), ("Show these shortcuts", "?"),
            ]),
        Group(
            title: "In a number field",
            rows: [("Change by 1", "↑ ↓"), ("Change by 10", "⇧ + ↑ ↓"), ("Scrub the value", "Drag the label")]),
    ]
}

/// "Keyboard shortcuts" (the ? key, or the toolbar's keyboard button): every key the editor answers, in groups.
struct ShortcutsSheet: View {
    let close: () -> Void

    var body: some View {
        CoreSheet("Keyboard shortcuts") {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    ForEach(ShortcutList.groups) { g in
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text(g.title).coreFont(size: MacTextSize.body, weight: .semibold)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(Array(g.rows.enumerated()), id: \.offset) { _, r in
                                HStack {
                                    Text(r.words)
                                    Spacer(minLength: Space.s3)
                                    Text(r.keys).monospaced().foregroundStyle(GlassInk.secondary)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: Space.s8 * 11)
        } footer: {
            Button("Done") { close() }.buttonStyle(.coreProminent)
                .keyboardShortcut(.cancelAction)
        }
        .accessibilityIdentifier("design-shortcuts")
    }
}
