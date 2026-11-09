import SwiftUI

/// One action of a state card or dialog footer.
public struct CoreAction {
    let title: String
    let key: ModalKey?
    let run: () -> Void
    public init(_ title: String, key: ModalKey? = nil, run: @escaping () -> Void) {
        self.title = title
        self.key = key
        self.run = run
    }
}

/// What a screen shows when it has nothing, is loading, or failed: an icon, a title, one plain line, then the actions with
/// the secondary on the left and the primary on the right. The one card for empty, error and offline states.
public struct CoreStateCard: View {
    let symbol: String
    let title: String
    let line: String
    let secondary: CoreAction?
    let primary: CoreAction?
    @Environment(\.corePalette) private var palette
    public init(
        symbol: String, title: String, line: String, secondary: CoreAction? = nil, primary: CoreAction? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.line = line
        self.secondary = secondary
        self.primary = primary
    }
    public var body: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: symbol).font(.system(size: MacTextSize.large, weight: .semibold))
                .foregroundStyle(palette.text2).accessibilityHidden(true)
            Text(title).font(.system(size: MacTextSize.title, weight: .semibold)).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(line).foregroundStyle(palette.text2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if secondary != nil || primary != nil {
                CoreDialogFooter(cancel: secondary, primary: primary)
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: Space.s8 * 11)
        .coreWell()
        .accessibilityElement(children: .contain)
    }
}

/// The one dialog footer: the way back on the left (`Cancel esc` unless the caller names another action), the main action on
/// the right with its key. `danger` makes the primary the red button.
public struct CoreDialogFooter: View {
    let cancel: CoreAction?
    let primary: CoreAction?
    let danger: Bool
    let busy: Bool
    public init(cancel: CoreAction?, primary: CoreAction?, danger: Bool = false, busy: Bool = false) {
        self.cancel = cancel
        self.primary = primary
        self.danger = danger
        self.busy = busy
    }
    public var body: some View {
        HStack(spacing: Space.s2) {
            if let cancel {
                Button(cancel.title, action: cancel.run).buttonStyle(CoreButtonStyle(.secondary))
                    .modifier(OptionalKey(key: cancel.key))
            }
            Spacer(minLength: Space.s3)
            if let primary {
                Button(primary.title, action: primary.run)
                    .buttonStyle(CoreButtonStyle(danger ? .danger : .prominent, busy: busy))
                    .modifier(OptionalKey(key: primary.key))
            }
        }
    }
}

private struct OptionalKey: ViewModifier {
    let key: ModalKey?
    @ViewBuilder func body(content: Content) -> some View {
        if let key { content.coreShortcut(key) } else { content }
    }
}

/// A placeholder block for content on its way: a soft well in whatever shape you pass, breathing between 0.5 and 1 opacity
/// (still at 0.75 under Reduce Motion). Size it with a frame.
public struct CoreSkeleton<S: Shape>: View {
    let shape: S
    @State private var beat = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    public init(_ shape: S) { self.shape = shape }
    public var body: some View {
        shape.fill(GlassInk.wellHover)
            .opacity(reduce ? 0.75 : beat ? 1 : 0.5)
            .animation(reduce ? nil : .easeInOut(duration: Motion.tick).repeatForever(autoreverses: true), value: beat)
            .onAppear { beat = true }
            .accessibilityHidden(true)
    }
}

extension CoreSkeleton where S == RoundedRectangle {
    public init() { self.init(coreShape(Radius.control)) }
}
