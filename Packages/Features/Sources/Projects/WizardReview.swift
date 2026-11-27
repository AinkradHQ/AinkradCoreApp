import CoreUI
import SwiftUI

/// The wizard's last step on its own, without the side card: the project as one summary, every choice on one row with
/// Change to go back to it. After Create it becomes the setup: the same header, the steps with live progress, a line
/// with what is happening now, and only the repos that need a look.
struct WizardReview: View {
    struct Row: Identifiable {
        let id: WizardStep
        let symbol: String
        let label: String
        let value: String
        var sub: String?
    }

    let name: String
    let colour: ProjectColour
    let kind: ProjectKind
    let rows: [Row]
    let creating: CreateProgress?
    let made: ProjectItem?
    let busy: Bool
    let go: (WizardStep) -> Void
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var started: Bool { made != nil || creating != nil }

    var body: some View {
        VStack(spacing: Space.s4) {
            hero
            if started {
                WizardSetupList(creating: creating, made: made, copy: made.map { WizardProgress($0.repos) })
                    .transition(.opacity.combined(with: .offset(y: coreMove(reduce, 8))))
                if let now = nowLine {
                    Text(now).foregroundStyle(palette.text2).frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.opacity)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { r in summaryRow(r) }
                }
                .padding(.vertical, Space.s1)
                .coreWell(radius: Radius.cardMac)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: Space.s8 * 18)
        .frame(maxWidth: .infinity)
        .animation(Motion.out(Motion.ui), value: started)
        .animation(Motion.out(Motion.ui), value: creating)
    }

    private var hero: some View {
        HStack(spacing: Space.s3) {
            ProjectMark(name: name, colour: colour, size: Space.s8 + Space.s5)
                .corePulse(creating != nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).coreFont(size: MacTextSize.large, weight: .semibold).accessibilityAddTraits(.isHeader)
                    .contentTransition(.opacity)
                Label(kind.title, systemImage: kind.symbol).foregroundStyle(palette.text2)
            }
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        if made != nil, creating == nil {
            return WizardProgress(made?.repos ?? []).title(name: name)
        }
        return started ? "Setting up \(name)" : "Ready to create \(name)"
    }

    /// What the Core is doing this moment, in plain words.
    private var nowLine: String? {
        guard let c = creating else {
            guard let made else { return nil }
            let p = WizardProgress(made.repos)
            return p.settled ? nil : "The Core is copying the code. You can open the project now; it keeps going."
        }
        switch c.stage {
        case .project:
            return c.total > 0
                ? "Making the project and reading \(min(c.total, 10)) repos from GitHub…" : "Making the project…"
        case .repos: return "Adding repo \(min(c.added + 1, c.total)) of \(c.total)…"
        case .finishing: return "Linking the Brain place and saving the settings…"
        }
    }

    private func summaryRow(_ r: Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Image(systemName: r.symbol).foregroundStyle(palette.text2).frame(width: Space.s5)
            Text(r.label).foregroundStyle(palette.text2).frame(width: Space.s8 * 3, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.value).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                if let sub = r.sub {
                    Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(2)
                }
            }
            Spacer(minLength: Space.s2)
            Button("Change") { go(r.id) }
                .buttonStyle(CoreButtonStyle(.plain, size: .small))
                .disabled(busy)
                .help("Go back to \(r.id.title)")
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
    }
}
