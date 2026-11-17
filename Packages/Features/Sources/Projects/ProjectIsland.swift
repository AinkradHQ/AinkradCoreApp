import CoreUI
import SwiftUI

/// An island: a titled card over the pane's surface.
struct Island<Content: View, Accessory: View>: View {
    let title: String
    let sub: String?
    let accessory: Accessory
    let content: Content
    init(
        title: String, sub: String? = nil, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.sub = sub
        self.accessory = accessory()
        self.content = content()
    }
    var body: some View {
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
        .coreWell(radius: Radius.pane)
        .clipShape(coreShape(Radius.pane))
        .accessibilityElement(children: .contain)
    }
}

extension Island where Accessory == EmptyView {
    init(_ title: String, sub: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, sub: sub, accessory: { EmptyView() }, content: content)
    }
}

/// A control whose feature is not built yet: the real control, off, with its reason as the tooltip.
struct Soon<Label: View>: View {
    let prominent: Bool
    let help: String
    @ViewBuilder let label: Label
    var body: some View {
        Button {
        } label: {
            label
        }
        .buttonStyle(CoreButtonStyle(prominent ? .prominent : .secondary)).disabled(true).help(help)
    }
}
