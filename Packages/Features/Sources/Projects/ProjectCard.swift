import CoreUI
import SwiftUI

/// The first letter of a project in its colour: the card's avatar, the space's top bar.
struct ProjectMark: View {
    let name: String
    let colour: ProjectColour
    var size: CGFloat = 28
    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .coreFont(size: size > 30 ? MacTextSize.title : MacTextSize.body, weight: .semibold)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(colour.fill, in: coreShape(size > 30 ? Radius.control : Radius.chip))
            .accessibilityHidden(true)
    }
}

/// A state as a word with its small square, on the card's thumbnail and in the space's top bar.
struct StateTag: View {
    let tag: ProjectItem.Tag
    var link: String?
    var body: some View {
        HStack(spacing: Space.s2) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(hue).frame(width: 8, height: 8)
            Text(word).lineLimit(1)
        }
        .coreFont(size: MacTextSize.body)
        .padding(.horizontal, Space.s2).frame(height: MacSize.controlMd)
        .background(GlassInk.card, in: coreShape(Radius.control))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(link.map { "\(label), \($0)" } ?? label)
    }
    private var label: String {
        switch tag {
        case .running: "Running"
        case .stopped: "Stopped"
        case .failed: "Failed"
        case .settingUp: "Setting up"
        case .new: "New"
        }
    }
    /// A running project shows its link where the others show their state.
    private var word: String { tag == .running ? (link ?? label) : label }
    private var hue: Color {
        switch tag {
        case .running: GlassInk.green
        case .failed: GlassInk.red
        case .settingUp: GlassInk.amber
        case .stopped, .new: GlassInk.slate
        }
    }
}

/// Press feedback for a card: a small settle, none under Reduce Motion.
private struct CardPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var system
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !ProjectsMotion.reduce(system) ? 0.985 : 1)
            .animation(Motion.out(Motion.press), value: configuration.isPressed)
    }
}

/// The sketch where the live preview goes: quiet bars in the shape of a page. Live previews of the running app replace it
/// with the run engine; until then a stopped project and a running one look the same, the stopped one greyer.
private struct ThumbnailPlaceholder: View {
    let dim: Bool
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            VStack(alignment: .leading, spacing: Space.s2) {
                bar(w * 0.18, 6)
                bar(w * 0.62, 28).padding(.top, Space.s1)
                HStack(spacing: Space.s2) {
                    ForEach(0..<4, id: \.self) { _ in bar(nil, 22) }
                }
                bar(w * 0.4, 6)
            }
            .padding(Space.s4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .opacity(dim ? 0.55 : 1)
        .accessibilityHidden(true)
    }
    private func bar(_ width: CGFloat?, _ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).fill(GlassInk.track.opacity(0.55))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

struct ProjectCard: View {
    let model: ProjectsModel
    let project: ProjectItem
    let index: Int
    let settled: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var system

    private var lit: Bool {
        #if DEBUG
        let forced = model.debugHover == project.id
        #else
        let forced = false
        #endif
        return hovering || model.cursor == project.id || forced
    }

    var body: some View {
        let reduce = ProjectsMotion.reduce(system)
        Button {
            model.openProject(project.id)
        } label: {
            VStack(alignment: .leading, spacing: Space.s3) {
                thumbnail
                info
            }
            .padding(Space.s2)
            .coreWell(radius: Radius.pane, active: lit)
            .contentShape(coreShape(Radius.pane))
        }
        .buttonStyle(CardPress())
        .offset(y: lit && !reduce ? -2 : 0)  // grid: ok a hover lift, not layout
        .opacity(settled ? 1 : 0)
        .offset(y: settled ? 0 : ProjectsMotion.rise(system))  // grid: ok the entrance
        .animation(Motion.out(Motion.reveal).delay(Double(min(index, 8)) * Motion.stagger), value: settled)
        .animation(Motion.out(Motion.hover), value: lit)
        .onHover { hovering = $0 }
        .contextMenu { Button("Open") { model.openProject(project.id) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(project.subtitle)")
        .accessibilityHint("Opens the project")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("project-card-\(project.slug)")
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(GlassInk.well)
            ThumbnailPlaceholder(dim: project.tag != .running)
            HStack(alignment: .bottom) {
                StateTag(tag: project.tag, link: project.link)
                Spacer(minLength: Space.s2)
                if lit { hoverActions.transition(.opacity) }
            }
            .padding(Space.s2)
        }
        .aspectRatio(1.6, contentMode: .fit)
        .clipShape(coreShape(Radius.control))
    }

    /// Open, and Start while it is stopped. Starting needs the run engine, so Start waits for it.
    private var hoverActions: some View {
        HStack(spacing: Space.s2) {
            if project.tag != .running {
                HoverAction(title: "Start", symbol: "play", enabled: false)
                    .help("Starting a project arrives with the run engine")
            }
            HoverAction(title: "Open", symbol: "arrow.right", enabled: true)
        }
    }

    private var info: some View {
        HStack(spacing: Space.s3) {
            ProjectMark(name: project.name, colour: model.colour(project), size: 36)
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

/// A label on the hovered card. The card is the button, so this only draws.
private struct HoverAction: View {
    let title: String
    let symbol: String
    let enabled: Bool
    var body: some View {
        HStack(spacing: Space.s1) {
            Image(systemName: symbol).coreFont(size: 10, weight: .bold)
            Text(title).coreFont(size: MacTextSize.body, weight: .semibold)
        }
        .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd)
        .foregroundStyle(enabled ? Color.white : GlassInk.secondary)
        .background(enabled ? GlassInk.blue : GlassInk.card, in: coreShape(Radius.control))
        .opacity(enabled ? 1 : 0.8)
        .accessibilityHidden(true)
    }
}

/// The last card of the gallery: start another.
struct NewProjectCard: View {
    let model: ProjectsModel
    let index: Int
    let settled: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var system

    var body: some View {
        let reduce = ProjectsMotion.reduce(system)
        Button {
            model.newProject()
        } label: {
            // The same bones as a project card, so the grid stays one height; the content is centred.
            VStack(spacing: Space.s3) {
                Color.clear.aspectRatio(1.6, contentMode: .fit)
                Color.clear.frame(height: 36)
            }
            .padding(Space.s2)
            .overlay {
                VStack(spacing: Space.s2) {
                    Image(systemName: "plus").coreFont(size: MacTextSize.large, weight: .regular)
                        .frame(width: 44, height: 44)
                        .background(hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac))
                        .padding(.bottom, Space.s1)
                    Text("New Project").coreFont(size: MacTextSize.title, weight: .semibold)
                    Text("Name it, add repos from GitHub").foregroundStyle(GlassInk.secondary)
                }
            }
            .background(hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.pane))
            .contentShape(coreShape(Radius.pane))
        }
        .buttonStyle(CardPress())
        .disabled(model.readOnly)
        .offset(y: hovering && !reduce ? -2 : 0)  // grid: ok a hover lift, not layout
        .opacity(settled ? 1 : 0)
        .offset(y: settled ? 0 : ProjectsMotion.rise(system))  // grid: ok the entrance
        .animation(Motion.out(Motion.reveal).delay(Double(min(index, 8)) * Motion.stagger), value: settled)
        .animation(Motion.out(Motion.hover), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityLabel("New Project")
        .accessibilityHint("Name it and add repos from GitHub")
        .accessibilityIdentifier("project-card-new")
    }
}

/// A card on its way: soft wells in the card's shape.
struct ProjectCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            CoreSkeleton(coreShape(Radius.control)).aspectRatio(1.6, contentMode: .fit)
            HStack(spacing: Space.s3) {
                CoreSkeleton(coreShape(Radius.control)).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreSkeleton(coreShape(Radius.chip)).frame(width: 120, height: 14)
                    CoreSkeleton(coreShape(Radius.chip)).frame(width: 180, height: 12)
                }
            }
            .padding(.horizontal, Space.s1).padding(.bottom, Space.s1)
        }
        .padding(Space.s2)
        .coreWell(radius: Radius.pane)
        .accessibilityHidden(true)
    }
}
