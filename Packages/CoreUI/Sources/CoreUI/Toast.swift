import SwiftUI

/// One toast. Every destructive action offers Undo.
public struct ToastItem: Identifiable, Sendable {
    public let id = UUID()
    public let message: String
    public let undo: (@Sendable @MainActor () -> Void)?
    public init(_ message: String, undo: (@Sendable @MainActor () -> Void)? = nil) {
        self.message = message
        self.undo = undo
    }
}

/// The toast surface: floating glass-card with the message and an optional Undo.
public struct CoreToast: View {
    let message: String
    let undo: (() -> Void)?
    @Environment(\.corePalette) private var palette

    public init(_ message: String, undo: (() -> Void)? = nil) {
        self.message = message
        self.undo = undo
    }

    public var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "checkmark.circle").foregroundStyle(palette.tone(.run).ink).accessibilityHidden(true)
            Text(message).font(.system(size: MacTextSize.body))
            if let undo {
                Button("Undo", action: undo).buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(palette.panelStrong, in: coreShape(Radius.cardMac))
        .background(coreShape(Radius.cardMac).fill(.regularMaterial).environment(\.colorScheme, .dark))
        .accessibilityElement(children: .contain)
    }
}

private struct ToastHost: ViewModifier {
    @Binding var item: ToastItem?
    let lifetime: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let item {
                    CoreToast(
                        item.message,
                        undo: item.undo.map { undo in
                            {
                                undo()
                                self.item = nil
                            }
                        }
                    )
                    .padding(Space.s4)
                    .transition(.opacity.combined(with: .offset(y: coreMove(reduce, Space.s4))))
                    .task(id: item.id) {
                        AccessibilityNotification.Announcement(item.message).post()
                        try? await Task.sleep(for: .seconds(lifetime))
                        if !Task.isCancelled { self.item = nil }
                    }
                }
            }
            .coreAnimation(Motion.out(Motion.move), value: item?.id)
    }
}

extension View {
    /// Shows a toast at the bottom; it leaves on its own after `lifetime` (the prototype's 2.6 s is close to two ticks).
    public func coreToast(_ item: Binding<ToastItem?>, lifetime: TimeInterval = Motion.tick * 2) -> some View {
        modifier(ToastHost(item: item, lifetime: lifetime))
    }
}
