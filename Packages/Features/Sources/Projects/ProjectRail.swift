import CoreUI
import SwiftUI

/// The thin icon rail of the space (details v2): one icon per module the project's kinds give it, Settings at the foot. Each
/// shows what it is for on hover; ⌘1, ⌘2… open them in the order they are shown. A module that needs you wears a small square.
struct ProjectRail: View {
    let model: ProjectsModel
    let project: ProjectItem

    private var modules: [ProjectModule] { ProjectModule.rail(for: project.allKinds) }
    private var needsYou: Bool { project.live?.sessions.contains { $0.state == .needsYou } ?? false }

    var body: some View {
        let order = modules + [.settings]
        VStack(spacing: Space.s1) {
            ForEach(Array(modules.enumerated()), id: \.element) { i, m in tile(m, key: i + 1) }
            Spacer(minLength: 0)
            tile(.settings, key: order.count)
        }
        .padding(.vertical, Space.s2).padding(.horizontal, Space.s1 + 2)
        .frame(width: Space.s8 + Space.s8 + Space.s6).frame(maxHeight: .infinity)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
    }

    private func tile(_ m: ProjectModule, key: Int) -> some View {
        RailTile(
            module: m, key: key, selected: model.module == m, marked: m == .ai && needsYou
        ) { model.module = m }
    }
}

private struct RailTile: View {
    let module: ProjectModule
    let key: Int
    let selected: Bool
    let marked: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: module.symbol).coreFont(size: MacTextSize.title, weight: .medium)
                .foregroundStyle(selected || hovering ? GlassInk.primary : GlassInk.secondary)
                .frame(width: Space.s8 + Space.s2, height: Space.s8 + Space.s2)
                .background(
                    selected ? GlassInk.lift(0.13) : hovering ? GlassInk.lift(0.07) : .clear,
                    in: coreShape(Radius.cardMac - 2)
                )
                .overlay(alignment: .topTrailing) {
                    if marked {
                        coreShape(2).fill(GlassInk.amber).frame(width: Space.s2, height: Space.s2)
                            .padding(Space.s1 + 1).transition(.opacity)
                    }
                }
                .contentShape(coreShape(Radius.cardMac - 2))
        }
        .buttonStyle(RailPress())
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .animation(Motion.out(Motion.ui), value: selected)
        .keyboardShortcut(key <= 9 ? KeyEquivalent(Character("\(key)")) : "0", modifiers: .command)
        .help("\(module.title)  ⌘\(key). \(module.help)\(marked ? ". A session needs you" : "")")
        .accessibilityLabel(module.title + (marked ? ", needs you" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("project-rail-\(module.title)")
    }
}

private struct RailPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduce
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduce ? 0.95 : 1)
            .animation(Motion.press(Motion.press), value: configuration.isPressed)
    }
}
