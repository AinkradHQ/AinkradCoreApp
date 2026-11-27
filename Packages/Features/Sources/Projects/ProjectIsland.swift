import CoreUI
import SwiftUI

/// An island: a titled card over the pane's surface.
public struct Island<Content: View, Accessory: View>: View {
    // TODO(design-system): proposal CoreIsland (a titled card over the pane's surface) and CoreSoonButton; Projects and Leyline both build them.
    let title: String
    let sub: String?
    let accessory: Accessory
    let content: Content
    public init(
        title: String, sub: String? = nil, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.sub = sub
        self.accessory = accessory()
        self.content = content()
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .center, spacing: Space.s2) {
                Text(title).coreFont(size: MacTextSize.headline, weight: .semibold).accessibilityAddTraits(.isHeader)
                if let sub { Text(sub).foregroundStyle(GlassInk.secondary).lineLimit(1) }
                Spacer(minLength: 0)
                accessory
            }
            content
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coreFrame(radius: Radius.pane, rim: Space.s1)
        .accessibilityElement(children: .contain)
    }
}

extension Island where Accessory == EmptyView {
    public init(_ title: String, sub: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, sub: sub, accessory: { EmptyView() }, content: content)
    }
}

/// A control whose feature is not built yet: the real control, off, with its reason as the tooltip.
public struct Soon<Label: View>: View {
    let prominent: Bool
    let help: String
    let label: Label
    public init(prominent: Bool, help: String, @ViewBuilder label: () -> Label) {
        self.prominent = prominent
        self.help = help
        self.label = label()
    }
    public var body: some View {
        Button {
        } label: {
            label
        }
        .buttonStyle(CoreButtonStyle(prominent ? .prominent : .secondary)).disabled(true).help(help)
    }
}
