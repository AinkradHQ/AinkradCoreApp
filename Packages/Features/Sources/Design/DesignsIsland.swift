import CoreUI
import Projects
import SwiftUI

/// The Designs island of a project's Overview: what is related to the project (designs, systems, mockups, brand kits and
/// files), newest first. A row opens it in Design; the accessory opens Design filtered to the project.
struct DesignsIsland: View {
    let model: DesignModel
    let project: ProjectRef

    private var list: [DesignItem] { model.linked(to: project.id) }

    var body: some View {
        Island(
            title: "Designs", sub: list.isEmpty ? nil : "\(list.count)",
            accessory: {
                CoreIconButton(symbol: "arrow.up.right", label: "Show \(project.name) in Design") {
                    model.show(project: project.id)
                }
                .disabled(!model.isConnected)
            }
        ) {
            if list.isEmpty, let why = Self.unavailable(model.load) {
                Text(why).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            } else if list.isEmpty {
                Text("No designs yet. Relate one from Design with its Projects menu.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Space.s1) {
                    ForEach(list.prefix(4)) { item in
                        CoreRow(
                            item.name, subtitle: subtitle(item), symbol: item.symbol,
                            action: { model.show(item: item.id) }
                        ) {
                            if let b = ItemBadge.of(item) { StateBadge(b.label, tone: b.tone, symbol: b.symbol) }
                        }
                        .contextMenu { DesignMenu(model: model, item: item) }
                        .help("Open \(item.name) in Design")
                    }
                }
            }
        }
        .accessibilityIdentifier("project-designs-island")
    }

    /// Why the island cannot list anything (so it never says "No designs yet" for a Core it could not ask).
    static func unavailable(_ load: DesignLoad) -> String? {
        switch load {
        case .ready: nil
        case .notConnected: "Not connected to a Core. Designs show here once this Mac is."
        case .loading: "Loading designs…"
        case .absent: "This Core has no Design yet."
        case .failed(let why): "Designs did not load. \(why)"
        }
    }

    private func subtitle(_ item: DesignItem) -> String {
        let when = Ago.words(item.date)
        return when.isEmpty ? item.kindWord.capitalizedFirst : "\(item.kindWord.capitalizedFirst) · \(when)"
    }
}
