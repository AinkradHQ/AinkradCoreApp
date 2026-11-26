import CoreUI
import SwiftUI

/// A card of the wall: the picture is the card (no frame around it), then the name with its kind's symbol and "project ·
/// when". Hover lifts it; the keyboard's card sits on a soft accent fill. A tap opens the item, a library file drags out as a
/// real file.
struct DesignCard: View {
    let model: DesignModel
    let item: DesignItem
    let index: Int
    let settled: Bool
    @State private var hovering = false
    @Environment(\.corePalette) private var palette

    private var lit: Bool {
        #if DEBUG
        hovering || model.debugHover == item.id
        #else
        hovering
        #endif
    }
    private var selected: Bool { model.selected == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Group {
                DesignThumb(model: model, item: item)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .frame(height: DesignCard.pictureHeight)
                    .background(lit ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac))
                    .clipShape(coreShape(Radius.cardMac))
            }
            .coreScaleEffect(lit ? 1.015 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s1) {
                    Image(systemName: item.symbol).coreFont(size: MacTextSize.meta, weight: .semibold)
                        .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                    Text(item.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                }
                HStack(spacing: Space.s2) {
                    Text(DesignCard.short(model, item)).coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).lineLimit(1)
                    if let b = ItemBadge.of(item) { StateBadge(b.label, tone: b.tone, symbol: b.symbol) }
                }
            }
            .padding(.horizontal, Space.s1)
            .help(item.name)
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? palette.btnPrimary.opacity(0.2) : .clear, in: coreShape(Radius.pane))
        .contentShape(coreShape(Radius.pane))
        .onTapGesture {
            model.selected = item.id
            model.openItem(item.id)
        }
        .coreRise(settled, index)
        .animation(Motion.out(Motion.hover), value: lit)
        .animation(Motion.out(Motion.hover), value: selected)
        .onHover { hovering = $0 }
        .modifier(DragOut(model: model, item: item))
        .contextMenu { DesignMenu(model: model, item: item) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.name), \(item.kindWord)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .coreActivates { model.openItem(item.id) }
        .accessibilityIdentifier("design-card-\(item.id)")
    }

    static let pictureHeight = Space.s8 * 5

    /// The card's second line: "Lanterna · 1 hr. ago", "No project · 24 KB", "Harbor · used by 2 designs".
    static func short(_ model: DesignModel, _ item: DesignItem) -> String {
        var parts = [item.projects.isEmpty ? "No project" : model.projectName(item.projects[0])]
        switch item {
        case .asset(let a): parts.append(Words.bytes(a.size))
        case .kit(let k): parts.append(Words.count(k.colors.count, "colour"))
        case .doc(let d):
            if d.kind == .system {
                parts.append("used by \(Words.count(model.usedBy(d).count, "design"))")
            } else if let at = d.updatedAt {
                parts.append(Ago.words(at))
            }
        }
        return parts.joined(separator: " · ")
    }

    /// "Lanterna · design system · updated 2 h ago", "No project · logo · 24 KB".
    static func line(_ model: DesignModel, _ item: DesignItem) -> String {
        var parts = [model.projectWords(item), item.kindWord]
        switch item {
        case .asset(let a): parts.append(Words.bytes(a.size))
        case .kit(let k): parts.append(Words.count(k.colors.count, "colour"))
        case .doc(let d):
            if d.kind == .system {
                parts.append("used by \(Words.count(model.usedBy(d).count, "design"))")
            } else if let at = d.updatedAt {
                parts.append("updated \(Ago.words(at))")
            }
        }
        return parts.joined(separator: " · ")
    }
}

/// A library file drags out as a file with its own name; designs and kits do not drag.
private struct DragOut: ViewModifier {
    let model: DesignModel
    let item: DesignItem
    func body(content: Content) -> some View {
        if case .asset(let a) = item, a.check == .ok {
            content.onDrag { model.dragProvider(a) }
        } else {
            content
        }
    }
}

/// What a card's badge says: a file still being checked or refused, or a design whose AI is paused. Nothing otherwise.
/// TODO(V6-02): Needs review / Approved. TODO(V7-02): Drawing.
struct ItemBadge {
    let label: String
    let tone: Tone
    let symbol: String

    static func of(_ item: DesignItem) -> ItemBadge? {
        switch item {
        case .asset(let a) where a.check == .pending: ItemBadge(label: "Checking…", tone: .queue, symbol: "hourglass")
        case .asset(let a) where a.check == .refused:
            ItemBadge(label: "Refused", tone: .fail, symbol: "exclamationmark.triangle")
        case .doc(let d) where d.aiPaused: ItemBadge(label: "AI paused", tone: .queue, symbol: "pause.circle")
        default: nil
        }
    }
}

/// The right-click menu of a card, an island row and the open item: Open, then the project links.
struct DesignMenu: View {
    let model: DesignModel
    let item: DesignItem
    var body: some View {
        Button("Open") { model.openItem(item.id) }
        Menu("Projects") {
            ForEach(model.allProjects) { p in
                let on = item.projects.contains(p.id)
                Button {
                    Task { await model.setLink(item, project: p, !on) }
                } label: {
                    if on { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                }
            }
        }
        .disabled(model.allProjects.isEmpty || model.readOnly)
    }
}

/// A card on its way: a soft well in the picture's shape and two lines.
struct DesignCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            CoreSkeleton(coreShape(Radius.cardMac)).frame(height: DesignCard.pictureHeight)
            VStack(alignment: .leading, spacing: Space.s1) {
                CoreSkeleton(coreShape(Radius.chip)).frame(width: Space.s8 * 4, height: Space.s3)
                CoreSkeleton(coreShape(Radius.chip)).frame(width: Space.s8 * 3, height: Space.s2)
            }
            .padding(.horizontal, Space.s1)
        }
        .padding(Space.s2)
        .accessibilityHidden(true)
    }
}
