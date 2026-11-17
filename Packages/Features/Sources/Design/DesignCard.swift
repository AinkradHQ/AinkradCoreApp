import CoreUI
import SwiftUI

/// A card of the wall: the thumbnail with its state badge, then the name and "project · what it is". Same bones as a project
/// card (well, hover lift, rise on arrival); a tap opens the item, a library file drags out as a real file.
struct DesignCard: View {
    let model: DesignModel
    let item: DesignItem
    let index: Int
    let settled: Bool
    @State private var hovering = false

    private var lit: Bool {
        #if DEBUG
        hovering || model.debugHover == item.id
        #else
        hovering
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ZStack(alignment: .topLeading) {
                DesignThumb(model: model, item: item)
                    .frame(height: Space.s8 * 5 + Space.s2)
                    .frame(maxWidth: .infinity)
                    .coreCard(GlassInk.well, radius: Radius.cardMac)
                    .clipShape(coreShape(Radius.cardMac))
                if let b = ItemBadge.of(item) {
                    StateBadge(b.label, tone: b.tone, symbol: b.symbol)
                        .padding(.horizontal, Space.s2).frame(height: MacSize.controlMd)
                        .coreCard(GlassInk.card, radius: Radius.control)
                        .padding(Space.s2)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                Text(DesignCard.line(model, item)).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            .padding(.horizontal, Space.s2).padding(.bottom, Space.s2)
            .help(item.name)
        }
        .padding(Space.s2)
        .coreWell(radius: Radius.pane, active: lit)
        .contentShape(coreShape(Radius.pane))
        .onTapGesture { model.openItem(item.id) }
        .coreScaleEffect(lit ? 1.01 : 1)
        .coreRise(settled, index)
        .animation(Motion.out(Motion.hover), value: lit)
        .onHover { hovering = $0 }
        .modifier(DragOut(model: model, item: item))
        .contextMenu { DesignMenu(model: model, item: item) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.name), \(item.kindWord)")
        .coreActivates { model.openItem(item.id) }
        .accessibilityIdentifier("design-card-\(item.id)")
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

/// A card on its way: soft wells in the card's shape.
struct DesignCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            CoreSkeleton(coreShape(Radius.cardMac)).frame(height: Space.s8 * 5 + Space.s2)
            VStack(alignment: .leading, spacing: Space.s1) {
                CoreSkeleton(coreShape(Radius.chip)).frame(width: Space.s8 * 4, height: Space.s4)
                CoreSkeleton(coreShape(Radius.chip)).frame(width: Space.s8 * 6, height: Space.s3)
            }
            .padding(.horizontal, Space.s2).padding(.bottom, Space.s2)
        }
        .padding(Space.s2)
        .coreWell(radius: Radius.pane)
        .accessibilityHidden(true)
    }
}
