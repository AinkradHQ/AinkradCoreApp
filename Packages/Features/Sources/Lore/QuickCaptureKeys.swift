// The quick capture shortcut (plan R6-05): a Carbon hot key, so no Accessibility permission is needed. Carbon delivers
// the key only to us and only while it is registered; it never reads other keys.
import AppKit
import Carbon.HIToolbox

/// A key and its modifiers, in Carbon's terms (what `RegisterEventHotKey` takes), plus the key's printed name.
public struct CaptureShortcut: Codable, Equatable, Sendable {
    public var key: UInt32
    public var mods: UInt32
    public var name: String

    /// ⇧⌘N (plan R7: taken only as asked).
    public static let standard = CaptureShortcut(key: UInt32(kVK_ANSI_N), mods: UInt32(cmdKey | shiftKey), name: "N")
    /// ⌥⌘N, used when another app holds the chosen shortcut.
    public static let fallback = CaptureShortcut(key: UInt32(kVK_ANSI_N), mods: UInt32(cmdKey | optionKey), name: "N")

    /// Apple's order: ⌃⌥⇧⌘, then the key.
    public var keys: String {
        var s = ""
        if mods & UInt32(controlKey) != 0 { s += "⌃" }
        if mods & UInt32(optionKey) != 0 { s += "⌥" }
        if mods & UInt32(shiftKey) != 0 { s += "⇧" }
        if mods & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + name
    }

    /// A key typed into the shortcut field. Nil without ⌘, ⌥ or ⌃: a plain letter would take that letter from every app.
    public init?(event: NSEvent) {
        let f = event.modifierFlags
        guard !f.intersection([.command, .option, .control]).isEmpty else { return nil }
        var mods: UInt32 = 0
        if f.contains(.command) { mods |= UInt32(cmdKey) }
        if f.contains(.shift) { mods |= UInt32(shiftKey) }
        if f.contains(.option) { mods |= UInt32(optionKey) }
        if f.contains(.control) { mods |= UInt32(controlKey) }
        let name = (event.charactersIgnoringModifiers ?? "").uppercased()
        guard !name.isEmpty, !name.contains(where: \.isNewline) else { return nil }
        self.init(key: UInt32(event.keyCode), mods: mods, name: name)
    }

    public init(key: UInt32, mods: UInt32, name: String) {
        self.key = key
        self.mods = mods
        self.name = name
    }
}

/// One global hot key at a time. The handler runs on the main thread (Carbon's application event target).
@MainActor final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private static var handler: EventHandlerRef?
    fileprivate static var fire: (@MainActor () -> Void)?

    init(fire: @escaping @MainActor () -> Void) {
        Self.fire = fire
        guard Self.handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                MainActor.assumeIsolated { GlobalHotKey.fire?() }
                return noErr
            }, 1, &spec, nil, &Self.handler)
    }

    var registered: Bool { ref != nil }

    /// False when another app (or the system) already holds it.
    func register(_ s: CaptureShortcut) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x414C_4F52), id: 1)  // 'ALOR'
        return RegisterEventHotKey(s.key, s.mods, id, GetApplicationEventTarget(), 0, &ref) == noErr && ref != nil
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
