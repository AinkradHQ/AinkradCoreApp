import SwiftUI

/// Sheet content: title, body, footer. Esc closes (the system sheet returns focus to the control that opened it).
public struct CoreSheet<Content: View, Footer: View>: View {
    let title: String
    let content: Content
    let footer: Footer
    @Environment(\.corePalette) private var palette

    public init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(title).font(.system(size: MacTextSize.title, weight: .semibold)).accessibilityAddTraits(.isHeader)
            content.font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2)
            HStack(spacing: Space.s2) {
                Spacer(minLength: 0)
                footer
            }
        }
        .padding(Space.s5)
        .frame(width: Space.s8 * 11)
        .background(palette.panelStrong)
        .coreTheme()
        .accessibilityElement(children: .contain)
    }
}

/// Confirm dialog: Esc cancels, Return runs the default button. Destructive confirms are secondary, never prominent, so Return is not a trap.
public struct CoreConfirmDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    let destructive: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    public init(
        _ title: String, message: String, confirmTitle: String, destructive: Bool = false,
        onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.destructive = destructive
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        CoreSheet(title) {
            Text(message).fixedSize(horizontal: false, vertical: true)
        } footer: {
            Button("Cancel", action: onCancel)
                .buttonStyle(CoreButtonStyle(destructive ? .prominent : .secondary))
                .keyboardShortcut(.cancelAction)
            Button(confirmTitle, action: onConfirm)
                .buttonStyle(CoreButtonStyle(destructive ? .secondary : .prominent))
                .keyboardShortcut(destructive ? nil : .defaultAction)
        }
    }
}

extension View {
    /// Presents a confirm dialog as a sheet. Closing (Esc, Cancel or confirm) returns focus to where it was.
    public func coreConfirm(
        _ title: String, isPresented: Binding<Bool>, message: String, confirmTitle: String, destructive: Bool = false,
        onConfirm: @escaping () -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            CoreConfirmDialog(
                title, message: message, confirmTitle: confirmTitle, destructive: destructive,
                onConfirm: {
                    isPresented.wrappedValue = false
                    onConfirm()
                },
                onCancel: { isPresented.wrappedValue = false })
        }
    }
}
