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

/// A sketch in the shape of the kind: three screens for a design, two pages for a mockup, swatches and "Aa" for a system.
struct DocSketch: View {
    let kind: DesignDoc.Kind
    var large = false

    var body: some View {
        let s: CGFloat = large ? 3 : 1
        switch kind {
        case .design:
            HStack(spacing: Space.s2 * s) {
                ForEach(0..<3, id: \.self) { i in screen(s, dark: i == 2) }
            }
            .accessibilityHidden(true)
        case .mockup:
            HStack(spacing: Space.s3 * s) {
                ForEach(0..<2, id: \.self) { _ in page(s) }
            }
            .accessibilityHidden(true)
        case .system:
            HStack(spacing: Space.s3 * s) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(Space.s6 * s), spacing: Space.s2 * s), count: 4),
                    spacing: Space.s2 * s
                ) {
                    ForEach(0..<8, id: \.self) { _ in
                        CoreSkeleton(coreShape(Radius.control)).frame(width: Space.s6 * s, height: Space.s6 * s)
                    }
                }
                .fixedSize()
                Text("Aa").coreFont(size: MacTextSize.large * s, weight: .semibold).foregroundStyle(GlassInk.secondary)
            }
            .accessibilityHidden(true)
        }
    }

    /// A phone-shaped well with bars where the header, rows and the main button go.
    private func screen(_ s: CGFloat, dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s1 * s) {
            CoreSkeleton(coreShape(Radius.chip)).frame(width: Space.s8 * s, height: Space.s2 * s)
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: Space.s1 * s) {
                    CoreSkeleton(coreShape(Radius.chip)).frame(width: Space.s2 * s, height: Space.s2 * s)
                    CoreSkeleton(coreShape(Radius.chip)).frame(height: Space.s1 * s)
                }
            }
            Spacer(minLength: 0)
            CoreSkeleton(coreShape(Radius.chip)).frame(height: Space.s3 * s)
        }
        .padding(Space.s2 * s)
        .frame(width: Space.s8 * 2 * s + Space.s2 * s, height: Space.s8 * 4 * s)
        .coreCard(dark ? GlassInk.wellHover : GlassInk.card, radius: Radius.control)
    }

    private func page(_ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Space.s2 * s) {
            CoreSkeleton(coreShape(Radius.chip)).frame(width: Space.s8 * s, height: Space.s2 * s)
            CoreSkeleton(coreShape(Radius.chip)).frame(height: Space.s4 * s)
            HStack(spacing: Space.s1 * s) {
                ForEach(0..<3, id: \.self) { _ in CoreSkeleton(coreShape(Radius.chip)).frame(height: Space.s5 * s) }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s2 * s)
        .frame(width: Space.s8 * 3 * s, height: Space.s8 * 4 * s)
        .coreCard(GlassInk.card, radius: Radius.control)
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
            } else if let img = model.images[asset.sha] {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .padding(large ? Space.s8 : Space.s4)
                    .frame(maxWidth: large ? Space.s8 * 12 : nil, maxHeight: large ? Space.s8 * 12 : nil)
                    .accessibilityLabel(asset.name)
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
            Image(systemName: "textformat").coreFont(size: large ? MacTextSize.large * 2 : MacTextSize.large)
                .foregroundStyle(GlassInk.secondary)
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
