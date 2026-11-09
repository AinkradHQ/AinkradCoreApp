import SwiftUI

/// A tone's symbol drawn in the tone's own ink, with no tile behind it. The ink of the light themes is pale, so the old
/// white glyph on an ink-coloured tile vanished (an empty white square); ink on the tinted surface always reads.
struct ToneGlyph: View {
    let symbol: String
    let ink: Color
    let size: CGFloat
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(ink)
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// An outcome or warning in place: a symbol, a bold line, a quiet line, an optional action, tinted by tone. The words carry
/// the state; the tone backs them up. Features use this instead of each drawing their own banner.
public struct CoreNotice<Action: View>: View {
    let symbol: String
    let title: String
    let text: String
    let tone: Tone
    let action: Action
    @Environment(\.corePalette) private var palette

    public init(
        symbol: String, title: String, text: String = "", tone: Tone = .queue, @ViewBuilder action: () -> Action
    ) {
        self.symbol = symbol
        self.title = title
        self.text = text
        self.tone = tone
        self.action = action()
    }

    public var body: some View {
        let c = palette.tone(tone)
        HStack(alignment: .top, spacing: Space.s3) {
            ToneGlyph(symbol: symbol, ink: c.ink, size: 26)
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text(title).coreFont(size: MacTextSize.headline, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                if !text.isEmpty {
                    Text(text).coreFont(size: MacTextSize.body).foregroundStyle(palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.s3)
            action
        }
        .padding(Space.s3)
        .background(c.ink.opacity(0.14), in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(c.ink.opacity(0.35), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.isEmpty ? title : "\(title). \(text)")
    }
}

extension CoreNotice where Action == EmptyView {
    public init(symbol: String, title: String, text: String = "", tone: Tone = .queue) {
        self.init(symbol: symbol, title: title, text: text, tone: tone) { EmptyView() }
    }
}

/// The panel of a dialog drawn over the shell (not a system sheet): a title and the content on a rounded glass panel.
public struct CoreDialogPanel<Content: View>: View {
    let title: String
    let width: CGFloat
    let content: Content
    @Environment(\.corePalette) private var palette

    public init(_ title: String, width: CGFloat = Space.s8 * 15, @ViewBuilder content: () -> Content) {
        self.title = title
        self.width = width
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            // An empty title leaves the header to the content (a sheet with its own hero).
            if !title.isEmpty { ModalHeader(title) }
            content
        }
        .foregroundStyle(palette.text)
        .coreFont(size: MacTextSize.body)
        .corePanel(radius: Radius.panel, padding: Space.s6)
        .frame(width: width)
        .shadow(color: .black.opacity(0.3), radius: 34, y: 14)
        .coreModalEntrance()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
