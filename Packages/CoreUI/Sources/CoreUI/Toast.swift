import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// What a toast says by symbol and tone, so the meaning is never colour alone (`shell.js` toast kinds).
public enum ToastKind: Sendable {
    case ok, info, warn, error
    var symbol: String {
        switch self {
        case .ok: "checkmark.circle"
        case .info: "info.circle"
        case .warn: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }
    var tone: Tone {
        switch self {
        case .ok: .run
        case .info: .queue
        case .warn: .warn
        case .error: .fail
        }
    }
}

/// One toast. Every destructive action offers Undo.
public struct ToastItem: Identifiable, Sendable {
    public let id = UUID()
    public let message: String
    public let kind: ToastKind
    public let undo: (@Sendable @MainActor () -> Void)?
    /// The button's words; Undo unless the action is something else (then ⌘Z does not trigger it).
    public let actionTitle: String
    /// Hover help for the message: the technical detail (an id) that the words leave out.
    public let help: String?
    public init(
        _ message: String, kind: ToastKind = .ok, actionTitle: String = "Undo", help: String? = nil,
        undo: (@Sendable @MainActor () -> Void)? = nil
    ) {
        self.help = help
        self.actionTitle = actionTitle
        self.message = message
        self.kind = kind
        self.undo = undo
    }
    /// An Undo stays longer than a plain message (prototype: 7 s against 3.5 s).
    public var lifetime: TimeInterval { undo == nil ? 3.5 : 7 }
}

/// The toast surface: floating glass-card with the message and an optional Undo.
public struct CoreToast: View {
    let message: String
    let kind: ToastKind
    let undo: (() -> Void)?
    let actionTitle: String
    let help: String?
    @Environment(\.corePalette) private var palette

    public init(
        _ message: String, kind: ToastKind = .ok, actionTitle: String = "Undo", help: String? = nil,
        undo: (() -> Void)? = nil
    ) {
        self.help = help
        self.actionTitle = actionTitle
        self.message = message
        self.kind = kind
        self.undo = undo
    }

    public var body: some View {
        HStack(spacing: Space.s3) {
            ToneGlyph(symbol: kind.symbol, ink: palette.tone(kind.tone).ink, size: 26)
            Text(message).coreFont(size: MacTextSize.body).help(help ?? "")
            if let undo {
                Button(actionTitle, action: undo).buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        }
        .foregroundStyle(GlassInk.primary)
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .coreGlass(radius: Radius.cardMac, interactive: false)
        .accessibilityElement(children: .contain)
    }
}

private struct ToastHost: ViewModifier {
    @Binding var item: ToastItem?
    let lifetime: TimeInterval?
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// The pointer on a toast holds it open; it counts down again when the pointer leaves.
    @State private var hovering = false
    /// VoiceOver's cursor is on the toast: it stays until the cursor leaves.
    @AccessibilityFocusState private var toastFocused: Bool

    /// With VoiceOver on, a toast stays three times as long: reading it takes longer than a glance.
    private var scale: Double {
        #if canImport(AppKit)
        NSWorkspace.shared.isVoiceOverEnabled ? 3 : 1
        #else
        1
        #endif
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let item {
                    CoreToast(
                        item.message, kind: item.kind, actionTitle: item.actionTitle, help: item.help,
                        undo: item.undo.map { undo in
                            {
                                undo()
                                self.item = nil
                            }
                        }
                    )
                    .onHover { hovering = $0 }
                    .accessibilityFocused($toastFocused)
                    // 52 pt up: clears the widget bar on Home (prototype)
                    .padding(.horizontal, Space.s4).padding(.bottom, Space.s8 + Space.s5)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: coreMove(reduce, Space.s4))),
                            removal: .opacity)
                    )
                    .task(id: item.id) { AccessibilityNotification.Announcement(item.message).post() }
                    .task(id: "\(item.id)-\(hovering)-\(toastFocused)") {
                        guard !hovering, !toastFocused else { return }
                        try? await Task.sleep(for: .seconds((lifetime ?? item.lifetime) * scale))
                        if !Task.isCancelled { self.item = nil }
                    }
                }
            }
            .background {
                // ⌘Z undoes the toast that is showing; in a text field it stays the field's own undo.
                if let undo = item?.undo, item?.actionTitle == "Undo" {
                    Button("Undo") {
                        #if canImport(AppKit)
                        if NSApp.keyWindow?.firstResponder is NSTextView {
                            NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                            return
                        }
                        #endif
                        undo()
                        item = nil
                    }
                    .keyboardShortcut("z", modifiers: .command).opacity(0).accessibilityHidden(true)
                }
            }
            .animation(Motion.calm(item == nil ? Motion.exit(0.25) : Motion.out(Motion.move), reduce), value: item?.id)
    }
}

extension View {
    /// Shows a toast at the bottom; it leaves on its own after `lifetime` (default: the item's own, longer with an Undo).
    public func coreToast(_ item: Binding<ToastItem?>, lifetime: TimeInterval? = nil) -> some View {
        modifier(ToastHost(item: item, lifetime: lifetime))
    }
}
