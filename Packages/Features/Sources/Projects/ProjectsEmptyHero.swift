import CoreUI
import SwiftUI

/// No projects yet: "What are you making?" and four tiles, one per kind, each a small looping picture. A tile opens the New
/// Project wizard with that kind already chosen. The header's actions stay hidden until there is a project.
struct ProjectsEmptyHero: View {
    let model: ProjectsModel
    @Environment(\.coreAccent) private var paneAccent
    @Environment(\.corePalette) private var palette
    @State private var shown = false

    var body: some View {
        VStack(spacing: Space.s6) {
            VStack(spacing: Space.s2) {
                Text("What are you making?").coreFont(size: 28, weight: .bold).tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
                Text("Pick one. Your code, notes and AI sessions then live together in one project.")
                    .foregroundStyle(palette.text2).multilineTextAlignment(.center)
                    .frame(maxWidth: 520).fixedSize(horizontal: false, vertical: true)
            }
            .coreRise(shown, 0)
            // An adaptive LazyVGrid ignores its column spacing (it rendered ~2 pt): fixed HStacks keep the gap.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Space.s4) { tiles(0..<4, rise: 1) }
                VStack(spacing: Space.s4) {
                    HStack(alignment: .top, spacing: Space.s4) { tiles(0..<2, rise: 1) }
                    HStack(alignment: .top, spacing: Space.s4) { tiles(2..<4, rise: 3) }
                }
            }
            if !model.readOnly {
                Button("Not Sure Yet? Start With a Name") { model.newProject() }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small))
                    .help("New Project  ⌘N")
                    .coreRise(shown, 5)
                    .accessibilityIdentifier("projects-empty-new")
            }
        }
        .frame(maxWidth: Space.s8 * 28)
        .padding(Space.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { shown = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projects-empty")
    }

    @ViewBuilder private func tiles(_ r: Range<Int>, rise: Int) -> some View {
        ForEach(Array(r), id: \.self) { i in
            let t = Self.tiles[i]
            KindTile(kind: t.kind, title: t.title, line: t.line, hue: GlassInk.accent(paneAccent)) {
                model.newProject(kind: t.kind)
            }
            .frame(width: Space.s8 * 6 + Space.s1, height: Space.s8 * 7)
            .coreRise(shown, rise + i - r.lowerBound)
        }
    }

    static let tiles: [(kind: ProjectKind, title: String, line: String)] = [
        (.web, "Web", "A site or web app, with a live preview."),
        (.app, "App", "A Mac, phone or desktop app you build and run."),
        (.infra, "Infra", "Servers, a platform or an operating system."),
        (.other, "Docs", "A book, research or a business. No code needed."),
    ]
}

/// One kind: its picture loops while the pointer is away; the tile lifts on hover and settles on press.
private struct KindTile: View {
    let kind: ProjectKind
    let title: String
    let line: String
    let hue: Color
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            KindPicture(kind: kind, hue: hue).frame(maxWidth: .infinity)
                .padding(.top, Space.s2)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title).coreFont(size: MacTextSize.title, weight: .semibold)
                Text(line).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: Space.s8 * 7, alignment: .topLeading)
        .projectCardSurface(lit: hovering)
        .contentShape(coreShape(Radius.pane))
        .onTapGesture(perform: action)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false })
        .coreScaleEffect(pressed ? 0.99 : 1)
        .offset(y: hovering && !pressed && !reduce ? -3 : 0)
        .animation(Motion.out(Motion.hover), value: hovering)
        .animation(Motion.out(Motion.press), value: pressed)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(line)")
        .coreActivates(action)
        .help("Start a \(title.lowercased()) project")
        .accessibilityIdentifier("projects-empty-\(kind.rawValue)")
    }
}
