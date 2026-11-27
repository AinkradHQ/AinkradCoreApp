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
    @State private var beat = false
    var body: some View {
        let b = project.badge
        StateBadge(project.tag == .running ? project.link : b.label, tone: b.tone, symbol: b.symbol)
            .opacity(project.tag == .starting && !project.archived && beat ? 0.55 : 1)
            .coreLoop(
                project.tag == .starting ? .easeInOut(duration: Motion.tick).repeatForever(autoreverses: true) : nil,
                value: beat
            )
            .onAppear { if project.tag == .starting { beat = true } }
            .accessibilityLabel("State: \(b.label)")
    }
}

struct ProjectCard: View {
    /// The mockup's picture height: 226, so a card is 300 tall.
    static let thumbHeight: CGFloat = 226
    let model: ProjectsModel
    let project: ProjectItem
    let index: Int
    let settled: Bool
    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduce

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
        .projectCardSurface(lit: lit)
        .contentShape(coreShape(Radius.pane))
        .onTapGesture { model.openProject(project.id) }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false }
        )
        // Hover lifts the card (not a scale); a press settles it back a touch.
        .coreScaleEffect(pressed ? 0.99 : 1)
        .offset(y: lit && !pressed && !reduce ? -3 : 0)
        .coreRise(settled, index)
        .animation(Motion.out(Motion.hover), value: lit)
        .animation(Motion.out(Motion.press), value: pressed)
        .onHover { hovering = $0 }
        .contextMenu { Button("Open") { model.openProject(project.id) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(project.name), \(project.subtitle)")
        .coreActivates { model.openProject(project.id) }
        .accessibilityIdentifier("project-card-\(project.slug)")
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottom) {
            Color.clear.coreCard(GlassInk.well, radius: Radius.control)
            ProjectPicture(project: project, colour: model.colour(project))
            HStack(alignment: .bottom) {
                ProjectStateBadge(project: project)
                    .padding(.horizontal, Space.s2).frame(height: MacSize.controlMd)
                    .coreCard(GlassInk.card, radius: Radius.control)
                Spacer(minLength: Space.s2)
                if lit { hoverActions.transition(.opacity) }
            }
            .padding(Space.s2)
        }
        .frame(height: ProjectCard.thumbHeight)
        .clipShape(coreShape(Radius.control))
    }

    /// Open, and Start while it is stopped. Starting needs the run engine, so Start waits for it.
    private var hoverActions: some View {
        HStack(spacing: Space.s2) {
            if project.tag != .running {
                Button {
                } label: {
                    Label("Start", systemImage: "play")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(true)
                .help("Starting a project arrives with the run engine")
            }
            Button {
                model.openProject(project.id)
            } label: {
                Label("Open", systemImage: "arrow.right")
            }
            .buttonStyle(CoreButtonStyle(.prominent, size: .small))
        }
    }

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
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        // The same bones as a project card, so the grid stays one height; the content is centred.
        VStack(spacing: Space.s3) {
            Color.clear.frame(height: ProjectCard.thumbHeight)
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
        .projectCardSurface(lit: hovering)
        .contentShape(coreShape(Radius.pane))
        .onTapGesture { if !model.readOnly { model.newProject() } }
        .offset(y: hovering && !reduce ? -3 : 0)
        .coreRise(settled, index)
        .animation(Motion.out(Motion.hover), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New Project")
        .coreActivates(enabled: !model.readOnly) { model.newProject() }
        .accessibilityIdentifier("project-card-new")
    }
}

/// A card on its way: soft wells in the card's shape.
struct ProjectCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            CoreSkeleton(coreShape(Radius.control)).frame(height: ProjectCard.thumbHeight)
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
        .projectCardSurface()
        .accessibilityHidden(true)
    }
}
