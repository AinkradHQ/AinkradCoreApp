import CoreUI
import SwiftUI

/// Copy, read, draft, room: where a new project stands. The Core copies the repos; drafting arrives with the run engine,
/// so while it is the step in progress the project stays here.
struct SettingUp: View {
    let project: ProjectItem
    private enum Step { case done, active, failed, waiting }

    private var steps: [(String, Step)] {
        let failed = project.repos.contains { $0.fetchError != nil }
        let copied = project.repos.allSatisfy { $0.fetchedAt != nil }
        let copy: Step = failed ? .failed : copied ? .done : .active
        return [
            ("Copy \(ProjectItem.count(project.repos.count, "repo")) to the Core", copy),
            ("Read the repos", copy == .done ? .done : .waiting),
            ("Draft the run from the repos", copy == .done ? .active : .waiting),
            ("Create the Brain room “\(project.name)”", .waiting),
        ]
    }

    var body: some View {
        VStack(spacing: Space.s3) {
            Text("Setting up \(project.name)").coreFont(size: MacTextSize.large, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: Space.s1) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                    CoreRow(s.0) { badge(s.1) }
                        .coreCard(s.1 == .active ? GlassInk.wellHover : .clear, radius: Radius.row)
                }
            }
            .frame(width: Space.s8 * 13)
            if let e = project.repos.compactMap(\.fetchError).first {
                Text(e).foregroundStyle(GlassInk.redInk).multilineTextAlignment(.center)
                    .frame(maxWidth: Space.s8 * 13)
            }
        }
    }

    private func badge(_ s: Step) -> StateBadge {
        switch s {
        case .done: StateBadge("Done", tone: .done, symbol: "checkmark.circle")
        case .active: StateBadge("In progress", tone: .warn, symbol: "gearshape")
        case .failed: StateBadge("Failed", tone: .fail, symbol: "exclamationmark.triangle")
        case .waiting: StateBadge("Waiting", tone: .queue, symbol: "clock")
        }
    }
}

/// "Ready to start": the drafted run in one line (See Changes, Undo) and what is still missing. Start waits for the secrets.
struct ReadyToStart: View {
    let project: ProjectItem
    let draft: RunDraft

    var body: some View {
        VStack(spacing: Space.s4) {
            Text("\(project.name) is ready to start").coreFont(size: MacTextSize.large, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "sparkle").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(summary).fixedSize(horizontal: false, vertical: true)
                    // The converter (P4) and its undo arrive with the run engine; the actions are in place for them.
                    HStack(spacing: Space.s1) {
                        Button("See Changes") {}.buttonStyle(CoreButtonStyle(.plain, size: .small)).disabled(true)
                        Button("Undo") {}.buttonStyle(CoreButtonStyle(.plain, size: .small)).disabled(true)
                    }
                    .help("The drafted run and its undo arrive with the run engine")
                }
            }
            .padding(Space.s3).frame(maxWidth: Space.s8 * 14, alignment: .leading)
            .coreCard(GlassInk.well, radius: Radius.cardMac)
            if !draft.secrets.isEmpty {
                Text(secretsLine).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: Space.s8 * 14)
            }
            HStack(spacing: Space.s2) {
                Soon(prominent: false, help: "Secrets arrive with the run engine") {
                    Label("Set Secrets…", systemImage: "key")
                }
                Soon(prominent: false, help: "Start stays off until the secrets are set") {
                    Label("Start", systemImage: "play")
                }
            }
        }
    }

    private var summary: AttributedString {
        var a = AttributedString("Run drafted from ")
        var f = AttributedString(draft.source)
        f.font = .system(size: MacTextSize.body, design: .monospaced)
        a += f
        a += AttributedString(": \(draft.services.count) services (\(draft.services.joined(separator: ", "))).")
        return a
    }

    private var secretsLine: AttributedString {
        var a = AttributedString("\(draft.secrets.count) secrets are needed before the first start: ")
        for (i, s) in draft.secrets.enumerated() {
            var n = AttributedString(s)
            n.font = .system(size: MacTextSize.body, design: .monospaced)
            a += n
            a += AttributedString(i < draft.secrets.count - 1 ? ", " : ".")
        }
        return a
    }
}
