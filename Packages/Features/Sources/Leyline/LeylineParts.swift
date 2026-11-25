import CoreUI
import SwiftUI

// Small pieces the Leyline page, the host panel and the host view share. Built from CoreUI parts only.

/// A page that is not there: nothing yet, loading failed, not connected. The Accounts and Connections state card: an icon
/// tile in its tone that bounces in, a title, the words and what to do about it as header-style action tiles.
struct LeylineStateCard<Actions: View>: View {
    @Environment(\.coreAccent) private var paneAccent
    let symbol: String
    let title: String
    let text: String
    var tone: Tone = .queue
    @ViewBuilder let actions: Actions
    @State private var shown = false
    var body: some View {
        let hue = tone == .fail ? GlassInk.red : tone == .warn ? GlassInk.amber : GlassInk.accent(paneAccent)
        VStack(spacing: Space.s3) {
            IconTile(symbol, hue: hue, size: Space.s8 * 2, bounce: shown)
                .coreScaleEffect(shown ? 1 : 0.6)
            Text(title).coreFont(size: MacTextSize.large, weight: .bold).accessibilityAddTraits(.isHeader)
            Text(text).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: Space.s8 * 16)
            HStack(spacing: Space.s2) { actions }.padding(.top, Space.s2)
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity)
        .coreWell()
        .overlay { if tone == .fail { coreShape(Radius.cardMac).strokeBorder(GlassInk.red, lineWidth: 1) } }
        .animation(.smooth(duration: 0.45), value: shown)
        .onAppear { shown = true }
        .accessibilityElement(children: .contain)
    }
}

extension LeylineStateCard where Actions == EmptyView {
    init(symbol: String, title: String, text: String, tone: Tone = .queue) {
        self.init(symbol: symbol, title: title, text: text, tone: tone) { EmptyView() }
    }
}

/// The loading state of Accounts and Connections: a bar, a word, and quiet cards where the hosts will be.
struct LeylineSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            CoreBusyBar().frame(maxWidth: Space.s8 * 5)
            Text("Loading…").foregroundStyle(GlassInk.secondary)
            ForEach(0..<4, id: \.self) { _ in
                Color.clear.frame(height: Space.s8 + Space.s6).coreWell()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The More menu's button on a well: a header tile's size by default, a medium control's beside medium buttons.
struct MoreButton: View {
    let items: [CoreDropdownItem]
    var side = MacSize.controlLg
    var body: some View {
        CoreDropdown(items: items) {
            Image(systemName: "ellipsis").coreFont(size: MacTextSize.body, weight: .semibold)
                .frame(width: side, height: side)
                .background(GlassInk.well, in: coreShape(Radius.control))
        }
        .help("More")
        .accessibilityLabel("More")
    }
}

/// A host's light: a small rounded square. Green answers, amber is slow, grey is offline or not checked yet. Always beside words.
struct StatusLight: View {
    let light: HostLight
    @Environment(\.corePalette) private var palette
    var body: some View {
        coreShape(2).fill(fill).frame(width: 7, height: 7).accessibilityHidden(true)
    }
    private var fill: Color {
        switch light {
        case .ok: palette.success
        case .slow: palette.warning
        case .off, .unknown: GlassInk.secondary.opacity(0.5)
        }
    }
}

/// The icon tile of a host card or row.
struct HostTile: View {
    let symbol: String
    var size: CGFloat = 34
    var body: some View {
        IconTile(symbol, hue: GlassInk.primary, size: size)
    }
}

/// The Core's emblem on an accent-soft tile.
struct CoreEmblemTile: View {
    var size: CGFloat = 44
    @Environment(\.corePalette) private var palette
    var body: some View {
        coreShape(size > 40 ? Radius.cardMac : Radius.control)
            .fill(palette.btnPrimary.opacity(0.22))
            .frame(width: size, height: size)
            .overlay { Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: size * 0.5) }
            .accessibilityHidden(true)
    }
}

/// A load as a thin bar, 0...100: blue, amber over 70, red over 85. The number is always said somewhere beside it.
struct LoadBar: View {
    let percent: Double
    var height: CGFloat = 3
    @Environment(\.corePalette) private var palette
    var body: some View {
        coreShape(height / 2).fill(palette.track)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    coreShape(height / 2).fill(Self.tone(percent, palette))
                        .frame(width: g.size.width * min(1, max(0, percent / 100)))
                }
            }
            .frame(height: height)
            .accessibilityHidden(true)
    }
    static func tone(_ p: Double, _ palette: Palette) -> Color {
        p > 85 ? palette.error : p > 70 ? palette.warning : palette.primary
    }
}

/// "Type to find a host" with ⌘K on it. The page focuses it with ⌘K; Esc clears it, then gives focus back.
struct FindField: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass").coreFont(size: MacTextSize.body, weight: .medium)
                .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            TextField("", text: $text, prompt: Text("Type to find a host").foregroundStyle(GlassInk.secondary))
                .textFieldStyle(.plain).focused(focus).onSubmit(onSubmit)
                .accessibilityLabel("Find a host")
                .accessibilityIdentifier("leyline-find")
            if text.isEmpty {
                CoreKeycap("⌘K")
            } else {
                CoreIconButton(symbol: "xmark", label: "Clear") { text = "" }
            }
        }
        .padding(.horizontal, Space.s3).frame(width: Space.s8 * 10 + Space.s5, height: MacSize.controlLg)
        .coreFieldSurface(focused: focus.wrappedValue)
        .onExitCommand {
            if text.isEmpty { focus.wrappedValue = false } else { text = "" }
        }
    }
}

/// The foot of the page, as in Accounts and Terminals: status chips at the left, the keys at the right.
struct LeylineFooter: View {
    let model: LeylineModel
    var body: some View {
        HStack(spacing: Space.s4) {
            if model.load == .ready, !model.fleet.isEmpty {
                HStack(spacing: Space.s2) {
                    AppStatChip("server.rack", Words.count(model.fleet.count, "host"), GlassInk.accent(paneAccent))
                    AppStatChip("checkmark.circle.fill", "\(model.onlineCount) online", GlassInk.green)
                    if model.fleet.count > model.onlineCount {
                        AppStatChip("moon.zzz.fill", "\(model.fleet.count - model.onlineCount) offline", GlassInk.slate)
                    }
                }
            }
            Spacer(minLength: 0)
            if model.load == .ready, !model.fleet.isEmpty, model.openID == nil {
                hint("↑↓←→", "Move")
                hint("⏎", "Terminal")
                hint("⌘2", "Files")
                hint("⌘3", "History")
                hint("type", "Find")
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
    }
    @Environment(\.coreAccent) private var paneAccent

    private func hint(_ keys: String, _ what: String) -> some View {
        HStack(spacing: Space.s2) {
            CoreKeycap(keys)
            Text(what).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The selected fill of a card or row (no outline): the accent, softly.
struct SelectedFill: ViewModifier {
    let selected: Bool
    let hover: Bool
    let radius: CGFloat
    @Environment(\.corePalette) private var palette
    func body(content: Content) -> some View {
        content.background(
            selected ? palette.btnPrimary.opacity(0.22) : hover ? GlassInk.wellHover : GlassInk.well,
            in: coreShape(radius))
    }
}
