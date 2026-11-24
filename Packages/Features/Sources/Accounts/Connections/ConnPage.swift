import CoreUI
import SwiftUI

/// The page under the header: the hero, then either the five cards (nothing connected yet) or a row per connection.
struct ConnListPage: View {
    let model: ConnectionsModel
    @State private var hovered: String?

    var body: some View {
        VStack(spacing: Space.s5) {
            ConnHero(
                kinds: model.kinds.map(\.id), connected: Set(model.shown.map(\.kind)), hovered: hovered,
                names: Dictionary(model.kinds.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            )
            .frame(maxWidth: .infinity)
            if model.shown.isEmpty { empty } else { list }
        }
        .frame(maxWidth: .infinity)
    }

    private func heading(_ title: String, _ line: String) -> some View {
        VStack(spacing: Space.s2) {
            Text(title).coreFont(size: MacTextSize.large + 8, weight: .semibold).accessibilityAddTraits(.isHeader)
            Text(line).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: Space.s8 * 15)
        }
    }

    /// Ainkrad signs in for you, so there is nothing to set up first.
    private var empty: some View {
        VStack(spacing: Space.s5) {
            heading(
                "Connect your tools",
                "Let your assistant read your code, tickets and chats, so it already knows the context when you ask.")
            HStack(spacing: Space.s5) {
                trust("lock", "You sign in on their website, never here")
                trust("eye", "Read only until you say so")
                trust("power", "Disconnect any time")
            }
            .coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
            HStack(alignment: .top, spacing: Space.s3) {
                ForEach(Array(model.kinds.enumerated()), id: \.element.id) { i, k in
                    ConnServiceCard(kind: k, hovered: $hovered) { model.beginAdd(kind: k.id) }.connRise(index: i)
                }
            }
        }
        .accessibilityIdentifier("connections-empty")
    }

    private func trust(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(text)
        }
    }

    private var list: some View {
        let free = model.kinds.filter { k in !model.shown.contains { $0.kind == k.id } }
        let anyUsed = model.shown.contains { $0.lastUsed != nil }
        return VStack(spacing: Space.s5) {
            heading(
                "\(model.shown.count) connected",
                "Your assistant reads them when it needs context. Nothing changes without the access you gave.")
            VStack(spacing: Space.s2) {
                ForEach(model.shown) { c in ConnRow(model: model, item: c, showUsed: anyUsed) }
            }
            if !free.isEmpty {
                HStack(spacing: Space.s3) {
                    Text("Add another").foregroundStyle(GlassInk.secondary)
                    ForEach(free) { k in ConnAddButton(kind: k, hovered: $hovered) { model.beginAdd(kind: k.id) } }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// A service on the empty page: logo, what it gives, what it reads, how long it takes. Connect shows on hover.
struct ConnServiceCard: View {
    let kind: ConnKind
    @Binding var hovered: String?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s2) {
                ConnLogo(kind: kind.id, size: 44, lit: hover)
                    .padding(.bottom, Space.s1)
                VStack(alignment: .leading, spacing: 0) {
                    Text(kind.name).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                    Text(kind.say).coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                chips
                HStack {
                    Text("About a minute").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    Spacer(minLength: Space.s2)
                    Text("Connect").coreFont(size: MacTextSize.meta, weight: .semibold)
                        .opacity(hover ? 1 : 0)
                }
                .padding(.top, Space.s1)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GlassInk.well, in: coreShape(Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.cardMac, hoverFill: true))
        .onHover {
            hover = $0
            hovered = $0 ? kind.id : (hovered == kind.id ? nil : hovered)
        }
        .animation(Motion.out(Motion.hover), value: hover)
        .accessibilityLabel("Connect \(kind.name). \(kind.say)")
    }

    private var chips: some View {
        let all = ConnLook.reads(kind.id)
        return ViewThatFits(in: .horizontal) {
            ForEach([3, 2, 1], id: \.self) { n in
                HStack(spacing: Space.s1) {
                    ForEach(all.prefix(n), id: \.self) { c in
                        Text(c).coreFont(size: MacTextSize.meta, weight: .medium).lineLimit(1).fixedSize()
                            .padding(.horizontal, Space.s2).padding(.vertical, Space.s1 / 2)
                            .background(GlassInk.wellHover, in: coreShape(Radius.chip))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: Space.s5, alignment: .leading)
        .clipped()
    }
}

/// A service not connected yet, as a small logo tile after "Add another".
struct ConnAddButton: View {
    let kind: ConnKind
    @Binding var hovered: String?
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) { ConnLogo(kind: kind.id, size: 36, lit: hover) }
            .buttonStyle(CoreQuietPressStyle(radius: Radius.control, hoverFill: true))
            .onHover {
                hover = $0
                hovered = $0 ? kind.id : (hovered == kind.id ? nil : hovered)
            }
            .help("Connect \(kind.name)")
            .accessibilityLabel("Connect \(kind.name)")
    }
}
