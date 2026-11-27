import CoreUI
import SwiftUI

/// The first letter of a project on its colour (one of the design system's accents): the card's avatar and the top bar's.
struct ProjectMark: View {
    let name: String
    let colour: ProjectColour
    var size: CGFloat = MacSize.controlLg
    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .coreFont(size: MacTextSize.title, weight: .semibold)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .coreCard(colour.fill, radius: Radius.control)
            .accessibilityHidden(true)
    }
}

/// A project's state as the design system's badge, on the card's thumbnail and in the space's top bar. A running project
/// shows its link where the others show their state.
struct ProjectStateBadge: View {
    let project: ProjectItem
    var body: some View {
        let b = project.badge
        StateBadge(project.tag == .running ? project.link : b.label, tone: b.tone, symbol: b.symbol)
            .accessibilityLabel("State: \(b.label)")
    }
}

/// The sketch where the live preview goes: quiet bars in the shape of a page. Live previews of the running app replace it
/// with the run engine; until then every project shows the same sketch.
private struct ThumbnailPlaceholder: View {
    var body: some View {
        GeometryReader { g in
            VStack(alignment: .leading, spacing: Space.s2) {
                bar(g.size.width * 0.18, Space.s2)
                bar(g.size.width * 0.62, Space.s6 + Space.s1).padding(.top, Space.s1)
                HStack(spacing: Space.s2) {
                    ForEach(0..<4, id: \.self) { _ in bar(nil, Space.s5) }
                }
                bar(g.size.width * 0.4, Space.s2)
            }
            .padding(Space.s4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityHidden(true)
    }
    private func bar(_ width: CGFloat?, _ height: CGFloat) -> some View {
        CoreSkeleton(coreShape(Radius.chip)).frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

struct ProjectCard: View {
    let model: ProjectsModel
    let project: ProjectItem
    let index: Int
    let settled: Bool
    @State private var hovering = false

    private var lit: Bool {
        #if DEBUG
        let forced = model.debugHover == project.id
        #else
        let forced = false
        #endif
        return hovering || model.cursor == project.id || forced
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            thumbnail
            info
        }
        .padding(Space.s2)
        .coreWell(radius: Radius.pane, active: lit)
        .contentShape(coreShape(Radius.pane))
        .onTapGesture { model.openProject(project.id) }
        .coreScaleEffect(lit ? 1.01 : 1)
        .coreRise(settled, index)
        .animation(Motion.out(Motion.hover), value: lit)
        .onHover { hovering = $0 }
        .contextMenu { CardMenu(model: model, project: project) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(project.name), \(project.subtitle)")
        .coreActivates { model.openProject(project.id) }
        .accessibilityIdentifier("project-card-\(project.slug)")
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottom) {
            Color.clear.coreCard(GlassInk.well, radius: Radius.control)
            ThumbnailPlaceholder().opacity(project.tag == .running ? 1 : 0.6)
            HStack(alignment: .bottom) {
                ProjectStateBadge(project: project)
                    .padding(.horizontal, Space.s2).frame(height: MacSize.controlMd)
                    .coreCard(GlassInk.card, radius: Radius.control)
                Spacer(minLength: Space.s2)
                if lit { hoverActions.transition(.opacity) }
            }
            .padding(Space.s2)
        }
        .aspectRatio(1.6, contentMode: .fit)
        .clipShape(coreShape(Radius.control))
    }

    private var hoverActions: some View { CardHoverActions(model: model, project: project) }

    private var info: some View {
        HStack(spacing: Space.s3) {
            ProjectMark(name: project.name, colour: model.colour(project))
            VStack(alignment: .leading, spacing: 0) {
                Text(project.name).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                Text(project.subtitle).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s1).padding(.bottom, Space.s1)
        .help(project.name)
    }
}

/// The last card of the gallery: start another.
struct NewProjectCard: View {
    let model: ProjectsModel
    let index: Int
    let settled: Bool
    @State private var hovering = false

    var body: some View {
        // The same bones as a project card, so the grid stays one height; the content is centred.
        VStack(spacing: Space.s3) {
            Color.clear.aspectRatio(1.6, contentMode: .fit)
            Color.clear.frame(height: MacSize.controlLg)
        }
        .padding(Space.s2)
        .overlay {
            VStack(spacing: Space.s2) {
                Image(systemName: "plus").coreFont(size: MacTextSize.large)
                    .frame(width: Space.s8 + Space.s3, height: Space.s8 + Space.s3)
                    .coreCard(hovering ? GlassInk.wellHover : GlassInk.well, radius: Radius.cardMac)
                    .padding(.bottom, Space.s1)
                Text("New Project").coreFont(size: MacTextSize.title, weight: .semibold)
                Text("Name it, add repos from GitHub").foregroundStyle(GlassInk.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        .coreCard(hovering ? GlassInk.wellHover : GlassInk.well, radius: Radius.pane)
        .contentShape(coreShape(Radius.pane))
        .onTapGesture { model.newProject() }
        .coreScaleEffect(hovering ? 1.01 : 1)
        .coreRise(settled, index)
        .animation(Motion.out(Motion.hover), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New Project")
        .coreActivates { model.newProject() }
        .accessibilityIdentifier("project-card-new")
    }
}

/// A card on its way: soft wells in the card's shape.
struct ProjectCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            CoreSkeleton(coreShape(Radius.control)).aspectRatio(1.6, contentMode: .fit)
            HStack(spacing: Space.s3) {
                CoreSkeleton(coreShape(Radius.control)).frame(width: MacSize.controlLg, height: MacSize.controlLg)
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreSkeleton(coreShape(Radius.chip)).frame(width: Space.s8 * 4, height: Space.s4)
                    CoreSkeleton(coreShape(Radius.chip)).frame(width: Space.s8 * 6, height: Space.s3)
                }
            }
            .padding(.horizontal, Space.s1).padding(.bottom, Space.s1)
        }
        .padding(Space.s2)
        .coreWell(radius: Radius.pane)
        .accessibilityHidden(true)
    }
}
