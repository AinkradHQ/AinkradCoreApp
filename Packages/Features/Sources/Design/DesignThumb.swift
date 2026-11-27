import AppKit
import CoreUI
import SwiftUI

/// What a card (or the open item's stage, `large`) shows of an item. A library file shows itself; a design, system or
/// mockup shows a quiet sketch of its kind until rendered previews exist (TODO(V3-02): the canvas renders real frames;
/// TODO(V6-02): approved Day/Night shots). A font is never loaded: it shows its name and its check state.
struct DesignThumb: View {
    let model: DesignModel
    let item: DesignItem
    var large = false

    var body: some View {
        Group {
            switch item {
            case .doc(let d): DocSketch(kind: d.kind, large: large)
            case .asset(let a): AssetPicture(model: model, asset: a, large: large)
            case .kit(let k): KitPicture(model: model, kit: k, large: large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A picture in the shape of the kind, drawn in the pane's accent until rendered previews exist (TODO(V6-02)): a fan of
/// three screens (day, night) for a design, a browser window for a mockup, colour steps and type for a system.
struct DocSketch: View {
    let kind: DesignDoc.Kind
    var large = false
    @Environment(\.coreAccent) private var paneAccent

    private var ink: Color { GlassInk.accent(paneAccent) }

    var body: some View {
        let s: CGFloat = large ? 2.6 : 0.85
        Group {
            switch kind {
            case .design:
                ZStack {
                    screen(s, night: false).rotationEffect(.degrees(-8)).offset(x: -44 * s, y: 4 * s)
                    screen(s, night: true).rotationEffect(.degrees(8)).offset(x: 44 * s, y: 4 * s)
                    screen(s, night: false).scaleEffect(1.06)
                }
            case .mockup: browser(s)
            case .system: system(s)
            }
        }
        .accessibilityHidden(true)
    }

    private func bar(_ w: CGFloat?, _ h: CGFloat, _ c: Color) -> some View {
        coreShape(h / 2).fill(c).frame(width: w, height: h)
    }

    /// A phone: an accent header, a few rows, the main button.
    private func screen(_ s: CGFloat, night: Bool) -> some View {
        let line = night ? Color.white.opacity(0.22) : Color.black.opacity(0.14)
        return VStack(alignment: .leading, spacing: 5 * s) {
            coreShape(4 * s).fill(ink.opacity(night ? 0.7 : 0.9)).frame(height: 22 * s)
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 4 * s) {
                    coreShape(3 * s).fill(line).frame(width: 10 * s, height: 10 * s)
                    VStack(alignment: .leading, spacing: 3 * s) {
                        bar(nil, 3 * s, line)
                        bar(CGFloat(18 + i * 6) * s, 3 * s, line.opacity(0.7))
                    }
                }
            }
            Spacer(minLength: 0)
            coreShape(4 * s).fill(ink).frame(height: 12 * s)
        }
        .padding(6 * s)
        .frame(width: 66 * s, height: 120 * s)
        .background(night ? Color(white: 0.11) : Color(white: 0.97), in: coreShape(10 * s))
        .shadow(color: .black.opacity(0.18), radius: 6 * s, y: 3 * s)
    }

    /// A browser window: the bar with its lights, a hero, three cards.
    private func browser(_ s: CGFloat) -> some View {
        let line = Color.black.opacity(0.14)
        return VStack(alignment: .leading, spacing: 6 * s) {
            HStack(spacing: 3 * s) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(line).frame(width: 5 * s, height: 5 * s) }
                bar(nil, 6 * s, line.opacity(0.6)).padding(.leading, 6 * s)
            }
            coreShape(5 * s)
                .fill(
                    LinearGradient(
                        colors: [ink, ink.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(height: 40 * s)
                .overlay(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 3 * s) {
                        bar(48 * s, 5 * s, .white.opacity(0.9))
                        bar(32 * s, 3 * s, .white.opacity(0.6))
                    }
                    .padding(.leading, 8 * s)
                }
            HStack(spacing: 5 * s) {
                ForEach(0..<3, id: \.self) { _ in coreShape(4 * s).fill(line).frame(height: 22 * s) }
            }
        }
        .padding(7 * s)
        .frame(width: 150 * s, height: 104 * s)
        .background(Color(white: 0.97), in: coreShape(8 * s))
        .shadow(color: .black.opacity(0.18), radius: 6 * s, y: 3 * s)
    }

    /// Colour steps of the accent and the greys, beside "Aa" and a button.
    private func system(_ s: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 14 * s) {
            VStack(spacing: 4 * s) {
                HStack(spacing: 4 * s) {
                    ForEach([1, 0.75, 0.5, 0.28], id: \.self) { o in
                        coreShape(4 * s).fill(ink.opacity(o)).frame(width: 18 * s, height: 18 * s)
                    }
                }
                HStack(spacing: 4 * s) {
                    ForEach([0.9, 0.6, 0.35, 0.15], id: \.self) { w in
                        coreShape(4 * s).fill(Color(white: w)).frame(width: 18 * s, height: 18 * s)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 5 * s) {
                Text("Aa").font(.system(size: 30 * s, weight: .semibold, design: .serif)).foregroundStyle(
                    GlassInk.primary)
                coreShape(4 * s).fill(ink).frame(width: 40 * s, height: 12 * s)
            }
        }
    }
}

/// A library file: its picture once loaded, or the state that keeps it from showing.
struct AssetPicture: View {
    let model: DesignModel
    let asset: DesignAsset
    var large = false

    var body: some View {
        Group {
            if asset.kind == .font {
                FontFace(asset: asset, large: large)
            } else if asset.check == .pending {
                Waiting(
                    symbol: asset.kind == .iconComposer ? "app.dashed" : "hourglass", line: "Checking…", large: large)
            } else if asset.check == .refused {
                Waiting(symbol: "exclamationmark.triangle", line: "Refused by the Core’s check", large: large)
            } else if let img = model.image(asset.sha) {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .padding(large ? Space.s8 : Space.s4)
                    .frame(maxWidth: large ? Space.s8 * 12 : nil, maxHeight: large ? Space.s8 * 12 : nil)
                    .accessibilityLabel(asset.name)
            } else if model.failedImages.contains(asset.sha) {
                VStack(spacing: Space.s2) {
                    Image(systemName: "exclamationmark.triangle").coreFont(
                        size: large ? MacTextSize.large * 2 : MacTextSize.large
                    )
                    .foregroundStyle(GlassInk.secondary)
                    if large { Text("The picture did not load.").foregroundStyle(GlassInk.secondary) }
                    Button("Retry") { model.retryImage(asset) }.buttonStyle(.coreSecondary)
                        .help("Fetch the picture again")
                }
                .accessibilityElement(children: .contain)
            } else {
                CoreSkeleton(coreShape(Radius.control)).frame(width: Space.s8 * 2, height: Space.s8 * 2)
            }
        }
        .task(id: asset.sha) { await model.loadImage(asset) }
    }
}

/// A font is listed by name only: the app never loads a font file (only the design helper parses fonts, V6-01).
struct FontFace: View {
    let asset: DesignAsset
    var large = false
    var body: some View {
        VStack(spacing: Space.s2) {
            // The app never loads the font itself, so the sample is set in the system serif.
            Text("Aa").font(.system(size: large ? 96 : 44, weight: .regular, design: .serif))
                .foregroundStyle(asset.check == .refused ? GlassInk.secondary : GlassInk.primary)
            if large {
                Text(asset.name).coreFont(size: MacTextSize.large, weight: .semibold).lineLimit(1)
                Text(state).foregroundStyle(GlassInk.secondary)
            }
        }
        .padding(Space.s4)
        .accessibilityElement(children: .combine)
    }
    private var state: String {
        switch asset.check {
        case .pending: "Checking… The design helper checks every font before designs use it."
        case .refused: "Refused by the Core’s check"
        case .ok: "Checked · \(Words.bytes(asset.size)) · a font preview comes from the design helper"
        }
    }
}

struct Waiting: View {
    let symbol: String
    let line: String
    var large = false
    var body: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: symbol).coreFont(size: large ? MacTextSize.large * 2 : MacTextSize.large)
            // On a card the badge already says it.
            if large { Text(line) }
        }
        .foregroundStyle(GlassInk.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// A brand kit: its logo (the item with role `logo`, else the first) beside its colours.
struct KitPicture: View {
    let model: DesignModel
    let kit: BrandKit
    var large = false

    var body: some View {
        let s: CGFloat = large ? 2 : 1
        HStack(spacing: Space.s4 * s) {
            if let logo = (kit.items.first { $0.role == "logo" } ?? kit.items.first).flatMap({ model.asset($0.sha) }) {
                AssetPicture(model: model, asset: logo).frame(width: Space.s8 * 3 * s, height: Space.s8 * 3 * s)
            }
            VStack(spacing: Space.s1 * s) {
                ForEach(Array(kit.colors.prefix(5).enumerated()), id: \.offset) { _, hex in
                    Swatch(hex: hex).frame(width: Space.s8 * s, height: Space.s4 * s)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kit.name): \(kit.colors.count) colours")
    }
}

/// One brand colour. The colour is the kit's own content (`#rrggbb` from the Core), not a UI colour, so it is the one place
/// this module turns a hex into a `Color`.
struct Swatch: View {
    let hex: String
    var body: some View {
        coreShape(Radius.chip).fill(Swatch.color(hex) ?? GlassInk.well)
            .help(hex)
    }

    static func color(_ hex: String) -> Color? {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return Color(
            red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
