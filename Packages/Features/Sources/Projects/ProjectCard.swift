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

/// A project's state as the design system's badge: always the state word (the link lives in the space's stage header).
/// `starting` is a Start that was asked for and has not shown yet: the word says so before the Core does.
struct ProjectStateBadge: View {
    let project: ProjectItem
    var starting = false
    @State private var beat = false

    private var isStarting: Bool { starting || (project.tag == .starting && !project.archived) }

    var body: some View {
        let b = starting ? ("Starting…", Tone.warn, "gearshape") : project.badge
        StateBadge(b.0, tone: b.1, symbol: b.2)
            // Starting breathes between full and 0.7 opacity (also under Reduce Motion: it is only a fade).
            .opacity(isStarting && beat ? 0.7 : 1)
            .animation(isStarting ? .easeInOut(duration: Motion.tick).repeatForever(autoreverses: true) : .default, value: beat)
            .task(id: isStarting) {
                beat = false
                if isStarting {
                    try? await Task.sleep(for: .milliseconds(30))
                    beat = true
                }
            }
            .contentTransition(.opacity)
            .accessibilityLabel("State: \(b.0)")
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

    /// A Start was asked for and the project has not started yet.
    private var startPending: Bool { model.controlling.contains(project.id) && project.tag != .running }
    private var starting: Bool { startPending || project.tag == .starting }

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
        .transition(reduce ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        .animation(Motion.out(Motion.hover), value: lit)
        .animation(Motion.out(Motion.press), value: pressed)
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
            ProjectPicture(project: project, colour: model.colour(project))
            // A soft floor under the hover buttons so they read on a light page.
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                .frame(height: Space.s8 * 2).opacity(lit ? 1 : 0).allowsHitTesting(false)
            HStack(alignment: .bottom) {
                Spacer(minLength: Space.s2)
                if lit { hoverActions.transition(.opacity) }
            }
            .padding(Space.s2)
            if starting { StartingLine().padding(.horizontal, Space.s2).padding(.bottom, Space.s1).transition(.opacity) }
        }
        .frame(height: ProjectCard.thumbHeight)
        .clipShape(coreShape(Radius.control))
        .animation(Motion.out(Motion.ui), value: starting)
    }

    private var hoverActions: some View { CardHoverActions(model: model, project: project) }

    private var info: some View {
        HStack(spacing: Space.s3) {
            ProjectMark(name: project.name, colour: model.colour(project))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s2) {
                    Text(project.name).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                    Spacer(minLength: 0)
                    ProjectStateBadge(project: project, starting: startPending && project.tag != .starting)
                }
                Text(project.subtitle).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, Space.s1).padding(.bottom, Space.s1)
        .help(project.kind == .web ? project.name : "\(project.name) · \(project.kind.title)")
    }
}

/// A thin line along the foot of a card's picture while the project starts: a block runs along it; under Reduce Motion the
/// whole line breathes instead.
struct StartingLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var on = false
    var body: some View {
        GeometryReader { g in
            coreShape(2).fill(GlassInk.wellHover)
                .overlay(alignment: .leading) {
                    coreShape(2).fill(Color.white.opacity(0.9)).frame(width: reduce ? g.size.width : g.size.width * 0.3)
                        .offset(x: reduce || !on ? 0 : g.size.width * 0.7)
                        .opacity(reduce ? (on ? 1 : 0.5) : 1)
                }
        }
        .frame(height: 3).clipShape(coreShape(2))
        .animation(.easeInOut(duration: reduce ? Motion.tick : 1.2).repeatForever(autoreverses: true), value: on)
        .onAppear { on = true }
        .accessibilityHidden(true)
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
        .transition(.opacity)
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
