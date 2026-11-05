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
            // Right-aligned by default; a footer that holds a Spacer spreads its buttons to both edges.
            HStack(spacing: Space.s2) { footer }.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(Space.s5)
        .frame(width: Space.s8 * 11)
        .coreGlass(radius: Radius.panel, interactive: false)
        .presentationBackground(.clear)
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
    @Environment(\.corePalette) private var palette

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
        ConfirmCard(
            title: title, message: message,
            choices: [
                ConfirmChoice("Cancel", symbol: "arrow.uturn.backward") { onCancel() },
                ConfirmChoice(confirmTitle, symbol: destructive ? "trash" : "checkmark", destructive: destructive) {
                    onConfirm()
                },
            ], cancel: onCancel
        )
        .presentationBackground(.clear)
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
