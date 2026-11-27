import CoreUI
import SwiftUI

/// No projects yet: what a project is, told as a picture. Repos flow into a project, the project runs as a live app;
/// three tiles say what you get, and one large New Project starts the wizard. The tiles float and the packets travel;
/// under Reduce Motion everything stands still.
struct ProjectsEmptyHero: View {
    let model: ProjectsModel
    @Environment(\.coreAccent) private var paneAccent
    @Environment(\.corePalette) private var palette
    @State private var shown = false

    var body: some View {
        let hue = GlassInk.accent(paneAccent)
        VStack(spacing: Space.s6) {
            ProjectFlowPicture(hue: hue).coreRise(shown, 0)
            VStack(spacing: Space.s2) {
                Text("Start your first project").coreFont(size: 28, weight: .bold).tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
                Text("A project keeps your code, notes and AI sessions in one place, and runs your app for you.")
                    .foregroundStyle(palette.text2).multilineTextAlignment(.center)
                    .frame(maxWidth: Space.s8 * 14).fixedSize(horizontal: false, vertical: true)
            }
            .coreRise(shown, 1)
            HStack(spacing: Space.s3) {
                feature(
                    "chevron.left.forwardslash.chevron.right", "Your code", "Pick repos from GitHub or paste a link.", 2
                )
                feature("sparkles", "AI sessions", "AI works on a private copy of the code.", 3)
                feature("play.rectangle", "Run and share", "Start the app and open it from anywhere.", 4)
            }
            .fixedSize(horizontal: false, vertical: true)
            if !model.readOnly {
                Button {
                    model.newProject()
                } label: {
                    Label("New Project", systemImage: "plus")
                }
                .buttonStyle(CoreButtonStyle(.prominent, size: .large))
                .help("New Project  ⌘N")
                .coreRise(shown, 5)
                .accessibilityIdentifier("projects-empty-new")
            }
        }
        .frame(maxWidth: Space.s8 * 22)
        .padding(Space.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { shown = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projects-empty")
    }

    private func feature(_ symbol: String, _ title: String, _ line: String, _ i: Int) -> some View {
        FeatureTile(symbol: symbol, title: title, line: line, hue: GlassInk.accent(paneAccent)).coreRise(shown, i)
    }
}

/// One "what you get" tile: its glyph bounces once when the pointer comes in.
private struct FeatureTile: View {
    let symbol: String
    let title: String
    let line: String
    let hue: Color
    @State private var hovering = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            IconTile(symbol, hue: hue, size: Space.s8 + Space.s1, bounce: hovering)
            Text(title).coreFont(size: MacTextSize.body, weight: .semibold)
            Text(line).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coreWell(radius: Radius.cardMac, active: hovering)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .accessibilityElement(children: .combine)
    }
}

/// Repos → Project → Live app, joined by dashed lines with packets running along them.
private struct ProjectFlowPicture: View {
    let hue: Color
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var up = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            tile("chevron.left.forwardslash.chevron.right", "Repos", lead: false, phase: 0)
            line
            tile("square.grid.2x2", "Project", lead: true, phase: 1)
            line
            tile("play.rectangle", "Live app", lead: false, phase: 2)
        }
        .onAppear { if !reduce { up = true } }
        .accessibilityHidden(true)
    }

    private var line: some View {
        TimelineView(.animation(paused: reduce)) { ctx in
            Canvas { g, size in
                let y = size.height / 2
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                g.stroke(
                    path, with: .color(palette.text2.opacity(0.35)), style: StrokeStyle(lineWidth: 2, dash: [4, 5]))
                let t = ctx.date.timeIntervalSinceReferenceDate
                for i in 0..<3 {
                    let p = reduce ? Double(i + 1) / 4 : (t * 0.45 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    g.fill(
                        Path(
                            roundedRect: CGRect(x: size.width * p - 3, y: y - 3, width: 6, height: 6), cornerRadius: 2),
                        with: .color(hue.opacity(sin(p * .pi))))
                }
            }
        }
        .frame(width: Space.s8 * 2, height: Space.s8 * 2 + Space.s4)
    }

    /// A glass tile that floats a few points, each on its own beat; the project in the middle is larger and in the accent.
    private func tile(_ symbol: String, _ label: String, lead: Bool, phase: Double) -> some View {
        let side: CGFloat = lead ? Space.s8 * 2 + Space.s6 : Space.s8 * 2 + Space.s4
        return VStack(spacing: Space.s2) {
            Image(systemName: symbol).font(.system(size: lead ? 34 : 26, weight: .medium))
                .foregroundStyle(lead ? .white : palette.text)
                .frame(width: side, height: side)
                .background(lead ? hue : GlassInk.wellHover, in: coreShape(Radius.pane))
            Text(label).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
        }
        .offset(y: up ? -4 : 0)
        .animation(reduce ? nil : .easeInOut(duration: 2.6).repeatForever().delay(phase * 0.5), value: up)
    }
}
