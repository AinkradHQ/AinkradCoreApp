import CoreUI
import SwiftUI

/// "What are you making?": the four kinds as tiles in one row, the chosen one marked.
struct WizardKindTiles: View {
    let kind: ProjectKind
    let pick: (ProjectKind) -> Void

    var body: some View {
        HStack(spacing: Space.s2) {
            ForEach(ProjectKind.allCases) { k in
                WizardChoiceTile(symbol: k.symbol, title: k.tileTitle, line: k.tagline, selected: kind == k) { pick(k) }
                    .accessibilityIdentifier("project-new-kind-\(k.rawValue)")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The Code step's one line when the repos corrected the kind: "Looks like an App: Swift, iOS · Change · Undo".
struct WizardCorrectionLine: View {
    let correction: KindCorrection
    let change: () -> Void
    let undo: () -> Void
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: correction.to.symbol).foregroundStyle(palette.text2)
            Text(correction.line).lineLimit(1)
            Spacer(minLength: Space.s2)
            Button("Change", action: change).buttonStyle(CoreButtonStyle(.plain, size: .small))
                .help("Pick the kind yourself")
            Button("Undo", action: undo).buttonStyle(CoreButtonStyle(.plain, size: .small))
                .help("Back to \(correction.from.tileTitle)")
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(GlassInk.well, in: coreShape(Radius.control))
        .accessibilityElement(children: .contain)
    }
}

/// Review, Brain: a new place named after the project, or one the person already keeps notes in.
struct WizardBrainChoice: View {
    let model: ProjectsModel
    let name: String
    @Binding var place: BrainPlace?
    @Binding var existing: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let places = model.places {
                HStack(spacing: Space.s2) {
                    WizardChoiceTile(
                        symbol: "plus.square", title: "New room · Best",
                        line: "A room named “\(name.trimmingCharacters(in: .whitespaces))”, just for this project.",
                        selected: !existing
                    ) { existing = false }
                    WizardChoiceTile(
                        symbol: "square.stack", title: "Use an existing room",
                        line: "Link a room you already keep notes in.", selected: existing,
                        why: places.isEmpty ? "Every room already belongs to a project." : nil
                    ) {
                        existing = true
                        if place == nil { place = places.first }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if existing, !places.isEmpty {
                    VStack(spacing: Space.s1) {
                        ForEach(places) { p in
                            CoreRow(p.name, symbol: "square.stack", selected: place == p) { place = p }
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: coreMove(reduce, -6))))
                }
            } else {
                Text("This Core has no Brain, so the project gets no room. You can turn the Brain on later.")
                    .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(Motion.out(Motion.ui), value: existing)
        .task { await model.loadPlaces() }
    }
}

/// Review, runner: where it runs (an app: where it builds). A choice that cannot be made says why.
struct WizardRunnerChoice: View {
    let model: ProjectsModel
    let kind: ProjectKind
    let appleCode: Bool
    @Binding var runner: WizardRunner
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                ForEach(WizardRunner.allCases, id: \.self) { r in
                    WizardChoiceTile(
                        symbol: r.symbol, title: r == .auto ? "\(r.title) · Best" : r.title,
                        line: r.line(model.runners, kind: kind), selected: runner == r,
                        why: r.unavailable(
                            kind: kind, runners: model.runners, supported: model.runnerSupported, appleCode: appleCode)
                    ) { runner = r }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if kind == .app {
                Text("Apple apps need a Mac to build. You can change this later.").foregroundStyle(palette.text2)
            }
        }
    }
}

/// Review, link: private to this Mac's Core, or a public link anyone can open.
struct WizardLinkChoice: View {
    let host: String
    @Binding var isPublic: Bool

    var body: some View {
        HStack(spacing: Space.s2) {
            WizardChoiceTile(
                symbol: "lock", title: "Private · Best", line: "Only you can open the project page.",
                selected: !isPublic
            ) { isPublic = false }
            WizardChoiceTile(
                symbol: "link", title: "Public link", line: "Anyone with \(host) sees the page, not your code.",
                selected: isPublic
            ) { isPublic = true }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
