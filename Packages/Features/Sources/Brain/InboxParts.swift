import CoreUI
import SwiftUI

/// A note inside a card: the CoreUI notice, toned by what it says. Red refuses, amber needs you, blue and slate inform.
struct InboxNote: View {
    let symbol: String
    let hue: Color
    let title: String
    let text: String
    init(_ symbol: String, _ hue: Color = GlassInk.slate, _ title: String, _ text: String = "") {
        self.symbol = symbol
        self.hue = hue
        self.title = title
        self.text = text
    }
    var body: some View {
        CoreNotice(
            symbol: symbol, title: title, text: text,
            tone: hue == GlassInk.red
                ? .fail
                : hue == GlassInk.amber
                    ? .warn : hue == GlassInk.blue ? .done : hue == GlassInk.green ? .run : .queue)
    }
}

/// Retrieved text, quoted and untrusted: shown as written, never run, never rendered as links or UI copy.
struct QuotedText: View {
    let text: String
    var body: some View {
        HStack(spacing: 0) {
            GlassInk.wellEdge.frame(width: 3)
            Text(verbatim: text).textSelection(.disabled).fixedSize(horizontal: false, vertical: true)
                .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GlassInk.well, in: coreShape(Radius.control))
        .clipShape(coreShape(Radius.control))
        .accessibilityLabel("Quoted text: \(text)")
    }
}

/// Where a text came from. The hover help says it is untrusted.
struct SourceBadge: View {
    let source: String
    var body: some View {
        Label(source, systemImage: "doc.text").coreFont(size: MacTextSize.meta).lineLimit(1)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, Space.s2).frame(height: MacSize.chip)
            .background(GlassInk.well, in: coreShape(Radius.chip))
            .help("Text from this source is untrusted. It is shown as written and never run.")
    }
}

/// A button label with its key beside it, like the prototype's "Approve ⌘↩".
struct KeyLabel: View {
    let title: String
    let key: String?
    init(_ title: String, key: String? = nil) {
        self.title = title
        self.key = key
    }
    var body: some View {
        HStack(spacing: Space.s2) {
            Text(title)
            if let key { Text(key).coreFont(size: MacTextSize.meta).opacity(0.7).accessibilityHidden(true) }
        }
    }
}

/// An inner card: a plain well with an optional red edge for something that needs a closer look.
struct InboxCardFrame<Content: View>: View {
    var edge: Color?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) { content }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .coreWell()
            .overlay { if let edge { coreShape(Radius.cardMac).strokeBorder(edge.opacity(0.7), lineWidth: 1) } }
    }
}

/// Type chip, bold title and age: the first line of a card.
struct CardHeader: View {
    let chip: String
    let hue: Color
    let title: String
    let age: String
    var body: some View {
        HStack(alignment: .center, spacing: Space.s2) {
            BrainChip(chip, hue)
            Text(title).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s2)
            Text(age).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
    }
}
