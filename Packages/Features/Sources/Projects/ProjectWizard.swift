import CoreUI
import SwiftUI

/// Every New Project: the guided wizard, three steps. What & name (the kind, the name, the colour), Code (optional, skipped
/// for "Anything else"), then Review (Brain room, runner and link as rows that open their choice in place). The project's
/// card builds on the right the whole way, on every step, so the dialog never changes shape.
struct ProjectWizard: View {
    let model: ProjectsModel
    let close: () -> Void
    @State private var d: WizardDraft
    @State private var linkText = ""
    @State private var linkError: String?
    /// Which way the last step change went, so the next page slides in from that side.
    @State private var forward = true
    /// The review row that shows its choice in place.
    @State private var editing: WizardRow?
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    init(model: ProjectsModel, draft: WizardDraft, editing: WizardRow? = nil, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        _d = State(initialValue: draft)
        _editing = State(initialValue: editing)
    }

    private var made: ProjectItem? { model.project(model.wizardProjectID) }
    /// The project is being made or already exists: the setup shows, nothing can be changed.
    private var started: Bool { made != nil || model.creating != nil || model.busy && d.step == .review }
    private var chosen: [PickRepo] { model.chosen(d.picked, pasted: d.pasted) }
    /// Repos GitHub told us about: a pasted link says nothing of what the code is, so it never corrects the kind.
    private var readable: Bool { chosen.contains { $0.fullName != nil } }
    private var suggestion: KindSuggestion { ProjectKind.suggest(from: chosen) }
    private var appleCode: Bool {
        chosen.contains { ["swift", "objective-c", "objective-c++"].contains($0.language?.lowercased() ?? "") }
    }
    /// GitHub is not connected and nothing was pasted: the code step asks to connect first.
    private var needsGithub: Bool {
        switch model.catalogState {
        case .unavailable, .failed: return d.pasted.isEmpty && !d.noCode
        default: return false
        }
    }
    /// Why Next waits on this step, in words; nil when it does not.
    private var whyNotNext: String? {
        switch d.step {
        case .what: d.whyNotNext
        case .code:
            needsGithub && d.kind != .other ? "Connect GitHub, paste a repo link, or start with no code." : nil
        case .review: nil
        }
    }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 28) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                HStack(alignment: .top, spacing: Space.s6) {
                    ScrollView {
                        Group {
                            switch d.step {
                            case .what: whatStep
                            case .code: codeStep
                            case .review: reviewStep
                            }
                        }
                        .id(d.step)
                        .transition(
                            .asymmetric(
                                insertion: .offset(x: coreMove(reduce, forward ? 12 : -12)).combined(with: .opacity),
                                removal: .opacity.animation(Motion.exit(0.15)))
                        )
                        .padding(.vertical, Space.s3)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.never)
                    .wizardEdgeFade()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    WizardPreviewCard(
                        name: d.name, colour: d.colour,
                        host: d.name.isEmpty || d.slugProblem != nil || !d.kind.hasPublicLink
                            ? nil : ProjectRules.host(made?.slug ?? d.slug),
                        repos: (made?.repos.map(\.name)) ?? chosen.map(\.name), runner: d.runner,
                        publicLink: d.publicLink, place: d.existingPlace ? d.place?.name : nil, kind: d.kind,
                        step: d.step
                    )
                }
                .frame(height: Space.s8 * 14 + Space.s4)
                footer
            }
        }
        .animation(Motion.out(Motion.ui), value: d.step)
        .animation(Motion.out(Motion.ui), value: d.moreOptions)
        .animation(Motion.out(Motion.ui), value: d.corrected)
        .onChange(of: d.name) { _, new in
            model.clearWizardError()
            if !d.colourPicked { d.colour = .standard(for: ProjectRules.slug(from: new)) }
        }
        .onChange(of: d.slugText) { _, _ in model.clearWizardError() }
        .onChange(of: suggestion) { _, _ in d.follow(suggestion, hasRepos: readable) }
        .onChange(of: d.kind) { _, _ in
            if d.runner.unavailable(
                kind: d.kind, runners: model.runners, supported: model.runnerSupported, appleCode: appleCode) != nil
            {
                d.runner = .auto
            }
        }
        .onDisappear { model.wizardDraft = model.draftToKeep(d, made: made != nil) }
        .task {
            d.follow(suggestion, hasRepos: readable)
            await model.loadPlaces()
        }
        .accessibilityIdentifier("project-new")
    }

    private func go(_ s: WizardStep) {
        forward = s.rawValue > d.step.rawValue
        if s == .code { d.wantsCode = true }
        editing = nil
        d.step = s
    }

    // MARK: header

    /// The step line only: the review's own title says what is being made, so it is never said twice.
    private var headline: String {
        return "Step \((d.steps.firstIndex(of: d.step) ?? 0) + 1) of \(d.steps.count) · \(d.step.title)"
    }

    private var header: some View {
        HStack(spacing: Space.s3) {
            HStack(spacing: Space.s1) {
                ForEach(d.steps, id: \.self) { s in
                    coreShape(Radius.chip / 3).fill(
                        s.rawValue <= d.step.rawValue ? palette.primary : palette.track
                    )
                    .frame(width: Space.s8 + Space.s3, height: Space.s1)
                }
            }
            .animation(Motion.out(Motion.move), value: d.step)
            .accessibilityHidden(true)
            Text(headline).foregroundStyle(palette.text2).contentTransition(.opacity)
            Spacer()
            // Not while the project is being made: it cannot be taken back, so Esc and the close wait too.
            if model.creating == nil, !model.busy {
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small)).help("Close (Esc). Your draft is kept.")
                    .coreShortcut(.escape)
                    .accessibilityLabel("Close")
            }
        }
        // The close button leaves while the project is made; the header keeps its height so nothing moves.
        .frame(height: MacSize.controlMd)
        .animation(Motion.out(Motion.ui), value: model.creating == nil)
    }

    // MARK: 1 · what and name

    private var whatStep: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            DialogHead(title: "What are you making?", line: "Pick one, then name it. You can change both later.")
            WizardKindTiles(kind: d.kind) { d.pickKind($0) }
            CoreTextField(
                "Name", placeholder: "Atlas notes", text: $d.name, error: d.nameProblem, autofocus: true,
                onSubmit: { if d.nameReady { go(d.next(.what)) } })
            VStack(alignment: .leading, spacing: Space.s1) {
                CoreFieldLabel("Colour")
                ColourSwatches(
                    selection: Binding(
                        get: { d.colour },
                        set: {
                            d.colour = $0
                            d.colourPicked = true
                        }))
            }
            if d.moreOptions || d.slugProblem != nil {
                VStack(alignment: .leading, spacing: Space.s3) {
                    CoreTextField(
                        "Link name", placeholder: "atlas-notes",
                        text: Binding(
                            get: { d.slug },
                            set: {
                                d.slugText = $0
                                d.slugEdited = true
                            }), error: d.slugProblem ?? model.wizardError,
                        onSubmit: { if d.nameReady { go(d.next(.what)) } }
                    )
                    .accessibilityIdentifier("project-new-link")
                    CoreTextField("Description", placeholder: "What it is, in a line (optional)", text: $d.description)
                }
                .transition(.opacity.combined(with: .offset(y: coreMove(reduce, -6))))
            } else {
                Button("More Options…") { d.moreOptions = true }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small))
                    .help("Change the link name or add a description")
                    .accessibilityIdentifier("project-new-more")
            }
        }
    }

    // MARK: 2 · code

    @ViewBuilder private var codeStep: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            DialogHead(
                title: d.kind == .other ? "Add code, if there is any" : "Pick your repos",
                line: d.kind == .other
                    ? "Not needed for this kind of project. Add repos that belong to it, or go on."
                    : "Core copies them, so your AI sessions can work on them.")
            if let c = d.corrected {
                WizardCorrectionLine(correction: c, change: { go(.what) }, undo: { d.undoCorrection() })
                    .transition(.opacity.combined(with: .offset(y: coreMove(reduce, -6))))
            }
            if needsGithub {
                githubCard.task { await model.loadCatalog() }
            } else {
                RepoPicker(model: model, picked: $d.picked, pasted: $d.pasted, height: nil)
            }
        }
    }

    private var githubCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(githubWords).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s2) {
                if githubFailed, !githubNeedsConnection {
                    Button("Try Again") { Task { await model.loadCatalog() } }
                        .buttonStyle(CoreButtonStyle(.secondary))
                } else {
                    Button("Connect GitHub", action: connectGithub).buttonStyle(.coreProminent)
                        .help("Your draft is kept. Come back with New Project.")
                }
                Button("Start With No Code") {
                    d.noCode = true
                    go(.review)
                }
                .buttonStyle(CoreButtonStyle(.secondary))
                .help("Make the project now and add repos later")
            }
            Text("Or paste the https link of a repo.").foregroundStyle(palette.text2)
            CoreTextField(
                "Repo link", placeholder: "https://github.com/owner/name", text: $linkText, error: linkError,
                onSubmit: addLink
            )
            .accessibilityIdentifier("project-new-paste")
            Button("Add Link", action: addLink).buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .disabled(linkText.trimmingCharacters(in: .whitespaces).isEmpty)
                .help(linkText.trimmingCharacters(in: .whitespaces).isEmpty ? "Paste a repo link first." : "")
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
    }

    private var githubFailed: Bool { if case .failed = model.catalogState { true } else { false } }
    private var githubNeedsConnection: Bool {
        if case .failed(let p) = model.catalogState { return p.needsConnection }
        return true
    }
    private var githubWords: String {
        if case .failed(let p) = model.catalogState { return p.words }
        return
            "Connect GitHub so Core can copy your repos. Core only reads the repos you pick; disconnect any time in Settings."
    }

    /// Connections opens behind a dialog, so the wizard steps aside with its draft kept: New Project picks it up again.
    private func connectGithub() {
        d.step = .code
        model.wizardDraft = d
        close()
        model.connectGithub()
        model.host.shell.showToast("Connect GitHub, then come back with New Project. Your draft is kept.")
    }

    /// A pasted link becomes a picked repo; one the Core would refuse is said here, before any Touch ID.
    private func addLink() {
        let t = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        guard let r = ProjectRules.repo(fromLink: t) else {
            linkError = ProjectRules.repoLinkProblem(t)
            return
        }
        linkError = nil
        if let listed = model.listed(r.url) {
            d.picked.insert(listed.id)
            linkText = ""
            return
        }
        let repo = PickRepo(org: "Pasted links", name: r.name, url: r.url)
        if !d.pasted.contains(where: { ProjectRules.same($0.url, repo.url) }) { d.pasted.append(repo) }
        d.picked.insert(d.pasted.first { ProjectRules.same($0.url, repo.url) }?.id ?? repo.id)
        linkText = ""
    }

    // MARK: 3 · review, then live progress

    private var reviewStep: some View {
        WizardReview(
            model: model, name: d.name, colour: d.colour, kind: d.kind, rows: reviewRows, chosen: chosen,
            editing: $editing,
            go: { go($0 == .kind ? .what : .code) }
        ) { row in
            switch row {
            case .brain: WizardBrainChoice(model: model, name: d.name, place: $d.place, existing: $d.existingPlace)
            case .runs:
                WizardRunnerChoice(model: model, kind: d.kind, appleCode: appleCode, runner: $d.runner)
            case .link: WizardLinkChoice(host: ProjectRules.host(d.slug), isPublic: $d.publicLink)
            default: EmptyView()
            }
        }
    }

    private var reviewRows: [WizardReviewItem] {
        d.reviewItems(repoNames: chosen.map(\.name), brainOn: model.places != nil)
    }

    // MARK: footer

    private var footer: some View {
        footerButtons.frame(height: Space.s8)
    }

    @ViewBuilder private var footerButtons: some View {
        if started {
            if made != nil, model.creating == nil, !model.busy {
                CoreDialogFooter(
                    cancel: CoreAction("Start Another", run: startAnother),
                    primary: CoreAction("Open Project", key: .primary) { model.openWizardProject() })
            } else {
                CoreDialogFooter(cancel: nil, primary: CoreAction("Setting up…") {}, busy: true)
            }
        } else {
            switch d.step {
            case .what:
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", run: close),
                    primary: CoreAction("Next", key: .primary) { go(d.next(.what)) }, enabled: d.nameReady,
                    why: whyNotNext)
            case .code:
                CoreDialogFooter(
                    cancel: CoreAction("Back") { go(.what) },
                    primary: CoreAction("Next", key: .primary) { go(.review) },
                    enabled: whyNotNext == nil, why: whyNotNext)
            case .review:
                CoreDialogFooter(
                    cancel: CoreAction("Back") { go(d.previous(.review)) },
                    primary: CoreAction("Create Project", key: .primary, run: create), busy: model.busy)
            }
        }
    }

    /// After a project was made here: forget it, and begin again with an empty wizard.
    private func startAnother() {
        model.wizardProjectID = nil
        model.wizardDraft = nil
        model.wizardMissed = []
        model.wizardIssues = []
        forward = false
        editing = nil
        d = WizardDraft()
    }

    private func create() {
        guard d.nameReady, !model.busy else { return }
        let d = d
        model.wizardDraft = d
        Task {
            await model.create(
                name: d.name, slug: d.slug, colour: d.colour, repos: chosen,
                expose: d.kind.hasPublicLink ? d.publicLink : false, runner: d.kind.runs ? d.runner.rawValue : "auto",
                description: d.description.trimmingCharacters(in: .whitespaces), autoSuffix: !d.slugEdited,
                wizard: true,
                place: d.existingPlace ? d.place : nil, kind: d.kind)
        }
    }
}
