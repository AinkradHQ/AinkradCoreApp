import SwiftUI

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
    public init(_ message: String, kind: ToastKind = .ok, undo: (@Sendable @MainActor () -> Void)? = nil) {
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
    @Environment(\.corePalette) private var palette

    public init(_ message: String, kind: ToastKind = .ok, undo: (() -> Void)? = nil) {
        self.message = message
        self.kind = kind
        self.undo = undo
    }

    public var body: some View {
        HStack(spacing: Space.s3) {
            IconTile(kind.symbol, hue: palette.tone(kind.tone).ink, size: 26)
            Text(message).font(.system(size: MacTextSize.body))
            if let undo {
                Button("Undo", action: undo).buttonStyle(CoreButtonStyle(.secondary, size: .small))
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

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let item {
                    CoreToast(
                        item.message, kind: item.kind,
                        undo: item.undo.map { undo in
                            {
                                undo()
                                self.item = nil
                            }
                        }
                    )
                    .onHover { hovering = $0 }
                    // 52 pt up: clears the widget bar on Home (prototype)
                    .padding(.horizontal, Space.s4).padding(.bottom, Space.s8 + Space.s5)
                    .transition(.opacity.combined(with: .offset(y: coreMove(reduce, Space.s4))))
                    .task(id: item.id) { AccessibilityNotification.Announcement(item.message).post() }
                    .task(id: "\(item.id)-\(hovering)") {
                        guard !hovering else { return }
                        try? await Task.sleep(for: .seconds(lifetime ?? item.lifetime))
                        if !Task.isCancelled { self.item = nil }
                    }
                }
            }
            .coreAnimation(Motion.out(Motion.move), value: item?.id)
    }
}

extension View {
    /// Shows a toast at the bottom; it leaves on its own after `lifetime` (default: the item's own, longer with an Undo).
    public func coreToast(_ item: Binding<ToastItem?>, lifetime: TimeInterval? = nil) -> some View {
        modifier(ToastHost(item: item, lifetime: lifetime))
    }
}
