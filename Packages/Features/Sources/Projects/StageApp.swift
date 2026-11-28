import CoreUI
import SwiftUI

/// The app stage: a phone and a Mac frame beside the latest build card. The steps are the Core's own start steps; with none
/// reported the card says so, and never invents a build number, a size or a time.
struct AppStage: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var target: String?

    /// The devices the repos are named for; with more than one, a switch picks the frame shown.
    private var platforms: [String] { ProjectKind.platforms(project.repos) }
    private var picked: String? { platforms.count > 1 ? (target.flatMap { platforms.contains($0) ? $0 : nil } ?? platforms[0]) : nil }
    private static let desktop: Set<String> = ["macOS", "Windows", "Linux", "Desktop"]

    var body: some View {
        VStack(spacing: Space.s4) {
            if let picked {
                CoreSegmented(
                    "Target", segments: platforms.map { CoreSegment($0, $0 == "iOS" ? "iPhone" : $0) },
                    selection: Binding(get: { picked }, set: { target = $0 }))
            }
            ViewThatFits(in: .horizontal) {
                content(mac: true)
                content(mac: false)
            }
        }
        .padding(.horizontal, Space.s6).padding(.vertical, Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(mac: Bool) -> some View {
        HStack(alignment: .center, spacing: Space.s8 + Space.s6) {
            HStack(alignment: .bottom, spacing: Space.s4 + 2) {
                let desktop = picked.map(Self.desktop.contains)
                if desktop != true { PhoneFrame(name: project.name, colour: model.colour(project)) }
                if desktop == true || (desktop == nil && mac) { MacFrame(colour: model.colour(project)) }
            }
            BuildCard(model: model, project: project).frame(maxWidth: Space.s8 * 13)
        }
        .fixedSize()
    }
}

private struct PhoneFrame: View {
    let name: String
    let colour: ProjectColour
    var body: some View {
        ZStack(alignment: .top) {
            coreShape(22).fill(
                LinearGradient(
                    colors: [colour.fill.opacity(0.95), colour.fill.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            )
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: Space.s2 + 2) {
                    Text(name).coreFont(size: MacTextSize.title, weight: .bold)
                    Text("Today").coreFont(size: MacTextSize.meta).opacity(0.85)
                    ForEach([34.0, 34, 70, 34], id: \.self) { h in
                        coreShape(8).fill(.white.opacity(0.18)).frame(height: h)
                    }
                }
                .foregroundStyle(.white).padding(.top, 34).padding(.horizontal, Space.s3 + 2)
            }
            .padding(10)
            coreShape(7).fill(Color(white: 0.07)).frame(width: 56, height: 14).padding(.top, 14)
        }
        .frame(width: 168, height: 340)
        .background(Color(white: 0.07), in: coreShape(30))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        .accessibilityHidden(true)
    }
}

private struct MacFrame: View {
    let colour: ProjectColour
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                // The traffic lights are the one place circles belong.
                ForEach(
                    [
                        Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                        Color(red: 0.16, green: 0.78, blue: 0.25),
                    ], id: \.self
                ) {
                    Circle().fill($0).frame(width: 8, height: 8)
                }
                Spacer()
            }
            .padding(.horizontal, Space.s2).frame(height: 22).background(Color(white: 0.165))
            HStack(spacing: 0) {
                Color(white: 0.137).frame(width: 70)
                LinearGradient(
                    colors: [colour.fill.opacity(0.55), Color(white: 0.12)], startPoint: .topLeading,
                    endPoint: .bottomTrailing)
            }
        }
        .frame(width: 300, height: 196).background(Color(white: 0.11)).clipShape(coreShape(10))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        .accessibilityHidden(true)
    }
}

/// "Latest build": its words, where it runs and its steps; failed it says which one and why.
private struct BuildCard: View {
    let model: ProjectsModel
    let project: ProjectItem

    private var steps: [StartStep] { project.live?.steps ?? [] }
    private var failed: Bool { steps.contains { $0.state == .failed } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3 + 2) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Latest build").foregroundStyle(GlassInk.secondary)
                Text(title).coreFont(size: MacTextSize.large, weight: .semibold).lineLimit(2)
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                fact("Target", ProjectKind.platforms(project.repos).joined(separator: " · "))
                fact("Runs on", project.live?.runner ?? model.coreName)
                fact(
                    "Built",
                    project.tag == .starting
                        ? "building now…" : project.run?.lastRun.map { "last run \($0)" } ?? "")
            }
            if steps.isEmpty {
                Text("No build yet. Build and Run makes the first one.").foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: Space.s1) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, s in BuildStep(step: s) }
                }
            }
            // Reveal .app and Download appear once the Core reports the build file; until then there is nothing to press.
        }
    }

    private var title: String {
        // The same builds the Builds island lists: a run that happened is a build, whatever its steps say.
        if steps.isEmpty { return project.run?.lastRun.map { "Built \($0)" } ?? "No build yet" }
        if failed { return "The last build failed" }
        return project.tag == .starting ? "Building \(project.name)" : "\(project.name) is built"
    }

    @ViewBuilder private func fact(_ k: String, _ v: String) -> some View {
        if !v.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                Text(k).foregroundStyle(GlassInk.secondary).lineLimit(1).frame(width: Space.s8 * 2, alignment: .leading)
                Text(v).lineLimit(1)
            }
        }
    }
}

/// One step of a build: a small square with a check, a cross or nothing; the one under way breathes and shows a bar.
private struct BuildStep: View {
    let step: StartStep
    var body: some View {
        HStack(spacing: Space.s2 + 2) {
            coreShape(5).fill(fill).frame(width: 18, height: 18)
                .overlay {
                    switch step.state {
                    case .done: Image(systemName: "checkmark").coreFont(size: 10, weight: .bold).foregroundStyle(.white)
                    case .failed: Text("!").coreFont(size: 11, weight: .bold).foregroundStyle(.white)
                    default: EmptyView()
                    }
                }
                .coreBreathing(step.state == .active)
            Text(step.title).lineLimit(1)
            if step.state == .active { CoreWorkingBar(width: 90) }
            Spacer(minLength: 0)
            if step.state == .failed, let d = step.detail {
                Text(d).foregroundStyle(GlassInk.redInk).lineLimit(1)
            } else if step.state == .done, let d = step.detail {
                Text(d).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, Space.s2 + 2).frame(height: 30)
        .coreCard(GlassInk.well, radius: Radius.control)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title), \(step.state.rawValue)\(step.detail.map { ", \($0)" } ?? "")")
    }

    private var fill: Color {
        switch step.state {
        case .done: GlassInk.green
        case .active: GlassInk.blue
        case .failed: GlassInk.red
        case .pending: GlassInk.lift(0.13)
        }
    }
}
