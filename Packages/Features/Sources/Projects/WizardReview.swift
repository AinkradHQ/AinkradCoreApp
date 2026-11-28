import CoreUI
import SwiftUI

/// One line of the review.
struct WizardReviewItem: Identifiable {
    let id: WizardRow
    let symbol: String
    let label: String
    let value: String
    var sub: String?
    /// False: nothing to change (the Core has no Brain).
    var changeable = true
}

/// The wizard's last step: the project as one summary, every choice on one row. Brain, runner and link open their choice
/// in place under the row (Change, then Done); kind and code go back to their step. After Create the same area becomes
/// the setup: the steps with live progress, a line with what is happening, and one row for each repo that needs the person.
struct WizardReview<Panel: View>: View {
    let model: ProjectsModel
    let name: String
    let colour: ProjectColour
    let kind: ProjectKind
    let rows: [WizardReviewItem]
    /// The repos asked for, to retry the ones the Core did not add.
    let chosen: [PickRepo]
    @Binding var editing: WizardRow?
    let go: (WizardRow) -> Void
    @ViewBuilder let panel: (WizardRow) -> Panel
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var creating: CreateProgress? { model.creating }
    private var made: ProjectItem? { model.project(model.wizardProjectID) }
    private var started: Bool { made != nil || creating != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            hero
            if started {
                WizardSetupList(
                    creating: creating, made: made, copy: made.map { WizardProgress($0.repos) },
                    requested: chosen.count, missed: model.wizardMissed.count
                )
                .transition(.opacity.combined(with: .offset(y: coreMove(reduce, 8))))
                if let now = nowLine {
                    Text(now).foregroundStyle(palette.text2).contentTransition(.opacity)
                }
                attention
            } else {
                // A create that failed comes back here: say why, plainly, above the choices that can fix it.
                if let e = model.writeError {
                    CoreNotice(
                        symbol: "exclamationmark.triangle", title: "\(name) was not created", text: e, tone: .warn
                    )
                    .transition(.opacity)
                }
                VStack(spacing: Space.s1) {
                    ForEach(rows) { r in
                        VStack(spacing: 0) {
                            WizardReviewRow(row: r, open: editing == r.id) {
                                if r.id == .kind || r.id == .code {
                                    go(r.id)
                                } else {
                                    editing = editing == r.id ? nil : r.id
                                }
                            }
                            if editing == r.id {
                                panel(r.id).padding(.horizontal, Space.s3).padding(.bottom, Space.s3)
                                    .transition(.opacity.combined(with: .offset(y: coreMove(reduce, -6))))
                            }
                        }
                    }
                }
                .padding(Space.s1)
                .background(GlassInk.well, in: coreShape(Radius.cardMac))
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Motion.out(Motion.ui), value: started)
        .animation(Motion.out(Motion.ui), value: editing)
        .animation(Motion.out(Motion.ui), value: creating)
    }

    private var hero: some View {
        HStack(spacing: Space.s3) {
            ProjectMark(name: name, colour: colour, size: Space.s8 + Space.s3)
                .opacity(creating != nil && reduce ? 0.85 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).coreFont(size: MacTextSize.large, weight: .semibold).accessibilityAddTraits(.isHeader)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        if made != nil, creating == nil {
            return WizardProgress(made?.repos ?? []).title(name: name, missed: model.wizardMissed.count)
        }
        return started ? "Setting up \(name)" : "Ready to create \(name)"
    }

    /// What the Core is doing this moment, in plain words; the counts are on the steps above, not repeated here.
    private var nowLine: String? {
        guard let c = creating else {
            guard let made else { return nil }
            return WizardProgress(made.repos).settled
                ? nil : "The Core is copying the code. You can open the project now; it keeps going."
        }
        switch c.stage {
        case .project: return c.total > 0 ? "Making the project and its first repos…" : "Making the project…"
        case .repos: return "Adding the rest of the repos…"
        case .finishing: return "Linking the Brain place and saving the settings…"
        }
    }

    // MARK: what needs the person

    /// Only what needs a look: repos that were not added or could not be copied, and anything the Core refused. One row
    /// for each repo, with the one action that fixes it.
    @ViewBuilder private var attention: some View {
        let bad = (made?.repos ?? []).filter { r in
            if case .ready = r.copy { return false }
            if case .fetching = r.copy { return false }
            return true
        }
        if !bad.isEmpty || !model.wizardMissed.isEmpty || !model.wizardIssues.isEmpty || model.writeError != nil {
            VStack(alignment: .leading, spacing: Space.s1) {
                if let made { ForEach(bad) { r in repoRow(made, r) } }
                ForEach(model.wizardMissed) { m in missedRow(m) }
                ForEach(model.wizardIssues, id: \.self) {
                    Text($0).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                }
                if let e = model.writeError { CoreFieldError(e) }
            }
            .transition(.opacity)
        }
    }

    private func missedRow(_ m: MissedRepo) -> some View {
        CoreRow(m.name, subtitle: m.why, symbol: "exclamationmark.triangle") {
            if let made, !m.why.contains("already"), let pick = chosen.first(where: { $0.name == m.name }) {
                Button("Try again") {
                    Task {
                        if await model.addRepos(to: made, [pick]) { model.wizardMissed.removeAll { $0.id == m.id } }
                    }
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.busy)
                .help(model.busy ? "Wait for the other change to finish." : "Add \(m.name) again")
            } else {
                Text("Not added").foregroundStyle(palette.error)
            }
        }
    }

    private func repoRow(_ p: ProjectItem, _ r: RepoItem) -> some View {
        CoreRow(r.name, subtitle: rowLine(r), symbol: r.copy.isFailed ? "exclamationmark.triangle" : "tray.full") {
            switch r.copy {
            case .ready: EmptyView()
            case .fetching: Text("Copying…").foregroundStyle(palette.text2)
            case .unknown:
                Button("Fetch now") { model.fetchRepo(p, r) }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
            case .failed(let why, _):
                if why.needsConnection {
                    Button("Connect GitHub") { model.connectGithub() }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                } else {
                    Button("Try again") { model.fetchRepo(p, r) }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
        }
    }

    private func rowLine(_ r: RepoItem) -> String? {
        switch r.copy {
        case .failed(let why, let text): why.needsConnection ? "This repo is private. Connect GitHub to copy it." : text
        case .fetching(let since): RepoCopy.elapsed(since: since, now: model.now())
        case .unknown: "The Core has not copied this repo yet."
        case .ready: nil
        }
    }
}

/// One summary row: glyph, label, the value (and a line under it), Change. Hover lifts the row.
private struct WizardReviewRow: View {
    let row: WizardReviewItem
    let open: Bool
    let change: () -> Void
    @State private var hovering = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Image(systemName: row.symbol).foregroundStyle(palette.text2).frame(width: Space.s5)
            Text(row.label).foregroundStyle(palette.text2).frame(width: Space.s8 * 3, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.value).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                if let sub = row.sub {
                    Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(2)
                }
            }
            Spacer(minLength: Space.s2)
            if row.changeable {
                Button(open ? "Done" : "Change", action: change)
                    .buttonStyle(CoreButtonStyle(.plain, size: .small))
                    .help(open ? "Keep this choice" : "Change \(row.label)")
                    .accessibilityIdentifier("project-new-change-\(row.id.rawValue)")
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(hovering && !open ? GlassInk.wellHover : .clear, in: coreShape(Radius.control))
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
    }
}
