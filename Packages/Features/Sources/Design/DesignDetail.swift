import CoreUI
import Projects
import SwiftUI

/// The open item: a top bar (back, name, what it is, its projects), the stage and an About island. For a design the stage is
/// its preview and the place the canvas goes; the canvas itself is V3-02 (TODO(V3-02): `DesignCanvasView` replaces the
/// placeholder), a mockup's viewer V3-07 (`MockupStage`) and a system's tokens and rules V3-06.
struct DesignDetail: View {
    let model: DesignModel
    let item: DesignItem

    var body: some View {
        VStack(spacing: Space.s2) {
            AppHeader {
                BackButton("Design") { model.closeItem() }
                Image(systemName: item.symbol).foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                Text(item.name).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(DesignCard.line(model, item)).foregroundStyle(GlassInk.secondary).lineLimit(1)
            } actions: {
                CoreDropdown(
                    items: projectItems,
                    isPresented: Binding(get: { model.projectsMenuOpen }, set: { model.projectsMenuOpen = $0 })
                ) {
                    Label("Projects", systemImage: "folder")
                }
                .disabled(model.allProjects.isEmpty || model.readOnly)
                .help("Relate this to projects; it stays in the library either way")
                .accessibilityIdentifier("design-projects")
            }
            .padding(.top, Space.s2)
            .frame(maxWidth: .infinity)
            .coreWell(radius: Radius.pane)
            HStack(alignment: .top, spacing: Space.s2) {
                stage
                AboutIsland(model: model, item: item).frame(width: Space.s8 * 10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("design-detail")
    }

    private var projectItems: [CoreDropdownItem] {
        model.allProjects.map { p in
            let on = item.projects.contains(p.id)
            return CoreDropdownItem(p.name, symbol: "folder", checked: on) {
                Task { await model.setLink(item, project: p, !on) }
            }
        }
    }

    @ViewBuilder private var stage: some View {
        if case .doc(let d) = item, d.kind == .mockup {
            MockupStage(model: model, doc: d)
                .padding(Space.s2)
                .coreWell(radius: Radius.pane)
                .contextMenu { DesignMenu(model: model, item: item) }
        } else {
            previewStage
        }
    }

    private var previewStage: some View {
        VStack(spacing: Space.s4) {
            DesignThumb(model: model, item: item, large: true)
            if let note = stageNote {
                Text(note).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                    .padding(.bottom, Space.s4)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coreWell(radius: Radius.pane)
        .modifier(StageDrag(model: model, item: item))
        .contextMenu { DesignMenu(model: model, item: item) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("design-stage")
    }

    private var stageNote: String? {
        guard case .doc(let d) = item else { return nil }
        switch d.kind {
        case .design: return "The canvas arrives with the next update: you will watch AI draw here, note and tweak."
        case .mockup: return nil
        case .system: return "Tokens, components and rules show here once design systems arrive, in a later update."
        }
    }
}

private struct StageDrag: ViewModifier {
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

/// What the item is: its facts as rows, then its projects, then (by kind) tags, colours, fonts or the designs that use it.
private struct AboutIsland: View {
    let model: DesignModel
    let item: DesignItem

    var body: some View {
        Island("About") {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s1) {
                    facts
                    heading("Projects")
                    if item.projects.isEmpty {
                        Text("Not related to a project. Use Projects in the top bar.").foregroundStyle(
                            GlassInk.secondary
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(item.projects, id: \.self) { id in
                            CoreRow(
                                model.projectName(id), symbol: "folder", action: { model.projectsModel.openSpace(id) }
                            )
                            .help("Open \(model.projectName(id))")
                        }
                    }
                    extra
                }
            }
            .scrollIndicators(.never)
        }
    }

    private func heading(_ t: String) -> some View {
        Text(t).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
            .padding(.top, Space.s3).padding(.bottom, Space.s1).accessibilityAddTraits(.isHeader)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(label).foregroundStyle(GlassInk.secondary).frame(width: Space.s8 * 3, alignment: .leading)
            Text(value).lineLimit(2).help(value)
            Spacer(minLength: 0)
        }
        .frame(minHeight: MacSize.controlSm)
        .accessibilityElement(children: .combine)
    }

    /// `session:as_…` is an AI session, anything else a person on a device.
    static func who(_ origin: String) -> String { origin.hasPrefix("session:") ? "An AI session" : "You" }

    @ViewBuilder private var facts: some View {
        switch item {
        case .doc(let d):
            fact("Kind", item.kindWord.capitalizedFirst)
            if d.kind == .design { fact("System", model.doc(d.system)?.name ?? "None") }
            fact("Updated", Ago.words(d.updatedAt))
            fact("Made by", Self.who(d.createdBy))
            if d.aiPaused { fact("AI", "Paused") }
        case .asset(let a):
            fact("Kind", item.kindWord.capitalizedFirst)
            fact("File", "\(a.contentType) · \(Words.bytes(a.size))")
            fact("Check", a.check == .ok ? "Passed" : a.check == .pending ? "Checking…" : "Refused")
            fact("Added", Ago.words(a.createdAt))
        case .kit(let k):
            fact("Kind", "Brand kit")
            fact("Holds", "\(Words.count(k.items.count, "file")) · \(Words.count(k.fonts.count, "font"))")
            fact("Updated", Ago.words(k.updatedAt))
        }
    }

    @ViewBuilder private var extra: some View {
        switch item {
        case .asset(let a) where !a.tags.isEmpty:
            heading("Tags")
            Text(a.tags.joined(separator: " · ")).fixedSize(horizontal: false, vertical: true)
        case .kit(let k):
            if !k.colors.isEmpty {
                heading("Colours")
                ForEach(k.colors, id: \.self) { hex in
                    HStack(spacing: Space.s2) {
                        Swatch(hex: hex).frame(width: Space.s6, height: Space.s4)
                        Text(hex.uppercased()).monospacedDigit()
                    }
                    .frame(minHeight: MacSize.controlSm)
                }
            }
            if !k.fonts.isEmpty {
                heading("Fonts")
                ForEach(k.fonts, id: \.self) { sha in
                    let f = model.asset(sha)
                    CoreRow(
                        f?.name ?? "A removed font",
                        subtitle: f.map {
                            $0.check == .ok ? "Checked" : $0.check == .pending ? "Checking…" : "Refused"
                        },
                        symbol: "textformat")
                }
            }
            if !k.items.isEmpty {
                heading("Files")
                ForEach(k.items, id: \.sha) { i in
                    if let a = model.asset(i.sha) {
                        CoreRow(
                            a.name, subtitle: i.role ?? DesignItem.asset(a).kindWord,
                            symbol: DesignItem.asset(a).symbol,
                            action: { model.openItem(DesignItem.asset(a).id) })
                    }
                }
            }
        case .doc(let d) where d.kind == .system:
            heading("Used by")
            let users = model.usedBy(d)
            if users.isEmpty { Text("No design uses it yet.").foregroundStyle(GlassInk.secondary) }
            ForEach(users) { u in
                CoreRow(
                    u.name, symbol: DesignCategory.screens.symbol, action: { model.openItem(DesignItem.doc(u).id) })
            }
        default: EmptyView()
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
