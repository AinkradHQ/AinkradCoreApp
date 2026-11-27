import CoreUI
import SwiftUI

/// The steps of the New Project wizard (D-30): name, code (GitHub first), what it is, Brain place, where it runs, review.
enum WizardStep: Int, CaseIterable {
    case name = 1
    case code, kind, brain, runs, review

    var title: String {
        switch self {
        case .name: "Name"
        case .code: "Code"
        case .kind: "Kind"
        case .brain: "Brain"
        case .runs: "Where it runs"
        case .review: "Review"
        }
    }
}

/// Every New Project: the guided wizard. The steps sit on the left; on the right the project's card builds as you go.
struct ProjectWizard: View {
    let model: ProjectsModel
    let close: () -> Void
    @State private var step = WizardStep.name
    @State private var name: String
    @State private var description = ""
    /// The link name once the person edits it; until then it follows the name.
    @State private var slugText = ""
    @State private var slugEdited = false
    /// The colour once the person picks one; until then it follows the name.
    @State private var colourPicked = false
    @State private var linkText = ""
    @State private var linkError: String?
    @State private var colour: ProjectColour
    @State private var picked: Set<String>
    @State private var pasted: [PickRepo] = []
    @State private var runner = WizardRunner.auto
    /// The existing Brain place to link; nil makes a new one named after the project.
    @State private var place: BrainPlace?
    @State private var existingPlace = false
    @State private var publicLink = false
    /// What it is: follows the repos until the person picks one.
    @State private var kind = ProjectKind.web
    @State private var kindPicked = false
    /// "Start with no code": the code step is passed with nothing picked.
    @State private var noCode = false
    @State private var creating = false
    /// Which way the last step change went, so the next page slides in from that side.
    @State private var forward = true
    /// Link name and description: folded away until asked for (or until the name needs a link name typed).
    @State private var moreOptions = false
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    init(
        model: ProjectsModel, name: String, picked: Set<String> = [], step: WizardStep = .name,
        pasted: [PickRepo] = [], close: @escaping () -> Void
    ) {
        self.model = model
        self.close = close
        _step = State(initialValue: step)
        _pasted = State(initialValue: pasted)
        _picked = State(initialValue: picked.union(pasted.map(\.id)))
        _name = State(initialValue: name)
        _colour = State(initialValue: .standard(for: ProjectRules.slug(from: name)))
    }

    private var slug: String { slugEdited ? slugText : ProjectRules.slug(from: name) }
    private var nameProblem: String? { name.isEmpty ? nil : ProjectRules.nameProblem(name) }
    private var slugProblem: String? { name.isEmpty ? nil : ProjectRules.slugProblem(slug) }
    private var nameReady: Bool { ProjectRules.nameProblem(name) == nil && ProjectRules.slugProblem(slug) == nil }
    private var made: ProjectItem? { model.project(model.wizardProjectID) }
    private var chosen: [PickRepo] { model.chosen(picked, pasted: pasted) }
    private var suggestion: KindSuggestion { ProjectKind.suggest(from: chosen) }
    /// A project that is not software has nothing to run, so the "where it runs" step is left out.
    private var steps: [WizardStep] { WizardStep.allCases.filter { $0 != .runs || kind.runs } }
    private func next(_ s: WizardStep) -> WizardStep { steps.first { $0.rawValue > s.rawValue } ?? .review }
    private func previous(_ s: WizardStep) -> WizardStep { steps.last { $0.rawValue < s.rawValue } ?? .name }
    private func followSuggestion() {
        if !kindPicked, step.rawValue >= WizardStep.kind.rawValue { kind = suggestion.kind }
    }
    /// GitHub is not connected and nothing was pasted: the code step asks to connect first.
    private var needsGithub: Bool {
        switch model.catalogState {
        case .unavailable, .failed: return pasted.isEmpty && !noCode
        default: return false
        }
    }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 28) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                HStack(alignment: .top, spacing: Space.s6) {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        Group {
                            switch step {
                            case .name: nameStep
                            case .code: codeStep
                            case .kind: WizardKindStep(kind: $kind, suggestion: suggestion, chosenByPerson: $kindPicked)
                            case .brain: brainStep
                            case .runs: runsStep
                            case .review: reviewStep
                            }
                        }
                        .id(step)
                        .transition(
                            .asymmetric(
                                insertion: .offset(x: coreMove(reduce, forward ? 24 : -24)).combined(with: .opacity),
                                removal: .opacity))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    if step != .review {
                        WizardPreviewCard(
                            name: name, colour: colour,
                            host: name.isEmpty || slugProblem != nil || !kind.hasPublicLink
                                ? nil : ProjectRules.host(slug),
                            repos: (made?.repos.map(\.name)) ?? chosen.map(\.name), runner: runner,
                            publicLink: publicLink,
                            place: existingPlace ? place?.name : nil, kind: kind, step: step,
                            progress: made.map { WizardProgress($0.repos) }
                        )
                        .transition(.opacity)
                    }
                }
                .frame(height: Space.s8 * 14 + Space.s4)
                footer
            }
        }
        .animation(Motion.out(Motion.move), value: step)
        .animation(Motion.out(Motion.ui), value: moreOptions)
        .onChange(of: name) { _, _ in model.clearWriteError() }
        .onChange(of: slugText) { _, _ in model.clearWriteError() }
        .onChange(of: suggestion) { _, _ in followSuggestion() }
        .task {
            model.wizardProjectID = nil
            followSuggestion()
        }
        .accessibilityIdentifier("project-new")
    }

    private func go(_ s: WizardStep) {
        forward = s.rawValue > step.rawValue
        step = s
        followSuggestion()
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: Space.s3) {
            HStack(spacing: Space.s1) {
                ForEach(steps, id: \.self) { s in
                    coreShape(Radius.chip / 3).fill(s.rawValue <= step.rawValue ? palette.primary : palette.track)
                        .frame(width: Space.s8 + Space.s3, height: Space.s1)
                }
            }
            .accessibilityHidden(true)
            Text("Step \((steps.firstIndex(of: step) ?? 0) + 1) of \(steps.count) · \(step.title)").foregroundStyle(
                palette.text2
            )
            .contentTransition(.opacity)
            Spacer()
            Button(action: close) { Image(systemName: "xmark") }
                .buttonStyle(CoreButtonStyle(.plain, size: .small)).help("Close (Esc)")
                .accessibilityLabel("Close")
        }
    }

    // MARK: 1 · name

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            DialogHead(title: "Name your project", line: "Short and clear. You can rename it later.")
            CoreTextField(
                "Name", placeholder: "Atlas notes", text: $name, error: nameProblem, autofocus: true,
                onSubmit: { if nameReady { go(.code) } })
            VStack(alignment: .leading, spacing: Space.s1) {
                CoreFieldLabel("Colour")
                ColourSwatches(
                    selection: Binding(
                        get: { colour },
                        set: {
                            colour = $0
                            colourPicked = true
                        }))
            }
            .onChange(of: name) { _, new in
                if !colourPicked { colour = .standard(for: ProjectRules.slug(from: new)) }
            }
            if moreOptions || slugProblem != nil {
                VStack(alignment: .leading, spacing: Space.s3) {
                    CoreTextField(
                        "Link name", placeholder: "atlas-notes",
                        text: Binding(
                            get: { slug },
                            set: {
                                slugText = $0
                                slugEdited = true
                            }), error: slugProblem ?? model.writeError, onSubmit: { if nameReady { go(.code) } }
                    )
                    .accessibilityIdentifier("project-new-link")
                    CoreTextField("Description", placeholder: "What it is, in a line (optional)", text: $description)
                }
                .transition(.opacity.combined(with: .offset(y: coreMove(reduce, -6))))
            } else {
                Button("More options…") { moreOptions = true }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small))
                    .help("Change the link name or add a description")
                    .accessibilityIdentifier("project-new-more")
            }
        }
    }

    // MARK: 2 · code

    @ViewBuilder private var codeStep: some View {
        if needsGithub {
            VStack(alignment: .leading, spacing: Space.s3) {
                DialogHead(title: "Add your code", line: "Connect GitHub so Core can copy your repos.")
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(githubWords).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.s2) {
                        if githubFailed, !githubNeedsConnection {
                            Button("Try again") { Task { await model.loadCatalog() } }
                                .buttonStyle(CoreButtonStyle(.secondary))
                        } else {
                            Button("Connect GitHub") { model.connectGithub() }.buttonStyle(.coreProminent)
                        }
                    }
                    Text("Or paste the https link of a repo.").foregroundStyle(palette.text2)
                    CoreTextField(
                        "Repo link", placeholder: "https://github.com/owner/name", text: $linkText, error: linkError,
                        onSubmit: addLink
                    )
                    .accessibilityIdentifier("project-new-paste")
                    Button("Add link", action: addLink).buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .disabled(linkText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                .coreCard(GlassInk.well, radius: Radius.cardMac)
            }
            .task { await model.loadCatalog() }
        } else {
            VStack(alignment: .leading, spacing: Space.s3) {
                DialogHead(title: "Pick your repos", line: "Core copies them, so your AI sessions can work on them.")
                RepoPicker(model: model, picked: $picked, pasted: $pasted, height: nil)
            }
        }
    }

    private var githubFailed: Bool { if case .failed = model.catalogState { true } else { false } }
    private var githubNeedsConnection: Bool {
        if case .failed(let p) = model.catalogState { return p.needsConnection }
        return true
    }
    private var githubWords: String {
        if case .failed(let p) = model.catalogState { return p.words }
        return "Core only reads the repos you pick. You can disconnect any time in Settings."
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
        let repo = PickRepo(org: "Pasted links", name: r.name, url: r.url)
        if !pasted.contains(where: { ProjectRules.same($0.url, repo.url) }) { pasted.append(repo) }
        picked.insert(pasted.first { ProjectRules.same($0.url, repo.url) }?.id ?? repo.id)
        linkText = ""
    }

    // MARK: 3 · Brain place

    private var brainStep: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            DialogHead(
                title: "Where should the Brain keep it?",
                line: "Notes, decisions and what the AI learns about this project live in a Brain place.")
            if let places = model.places {
                HStack(spacing: Space.s2) {
                    WizardChoiceTile(
                        symbol: "plus.square", title: "New place · Best",
                        line: "A place named “\(name.trimmingCharacters(in: .whitespaces))”, just for this project.",
                        selected: !existingPlace
                    ) { existingPlace = false }
                    WizardChoiceTile(
                        symbol: "square.stack", title: "Use an existing place",
                        line: places.isEmpty
                            ? "Every place already belongs to a project." : "Link a place you already keep notes in.",
                        selected: existingPlace
                    ) {
                        guard !places.isEmpty else { return }
                        existingPlace = true
                        if place == nil { place = places.first }
                    }
                    .disabled(places.isEmpty)
                }
                .fixedSize(horizontal: false, vertical: true)
                if existingPlace {
                    ScrollView {
                        VStack(spacing: Space.s1) {
                            ForEach(places) { p in
                                CoreRow(p.name, symbol: "square.stack", selected: place == p) { place = p }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: Space.s8 * 5)
                    .scrollIndicators(.never)
                    .transition(.opacity.combined(with: .offset(y: coreMove(reduce, -6))))
                }
            } else {
                Text("This Core has no Brain, so the project gets no place. You can turn the Brain on later.")
                    .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(Motion.out(Motion.ui), value: existingPlace)
        .task { await model.loadPlaces() }
    }

    // MARK: 4 · where it runs

    private var runsStep: some View {
        WizardRunsStep(
            model: model, kind: kind, runner: $runner, publicLink: $publicLink, host: ProjectRules.host(slug))
    }

    // MARK: 4 · review, then live progress

    private var reviewStep: some View {
        VStack(spacing: Space.s3) {
            WizardReview(
                name: name, colour: colour, kind: kind, rows: reviewRows, creating: model.creating, made: made,
                busy: model.busy, go: go)
            // Only what needs a look: repos that could not be copied or added, and anything the Core refused.
            let attention = (made?.repos ?? []).filter { r in
                if case .ready = r.copy { return false }
                if case .fetching = r.copy { return false }
                return true
            }
            if !attention.isEmpty || !model.wizardMissed.isEmpty || !model.wizardIssues.isEmpty
                || model.writeError != nil
            {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        if let made { ForEach(attention) { r in repoRow(made, r) } }
                        ForEach(model.wizardMissed) { m in
                            CoreRow(m.name, subtitle: m.why, symbol: "exclamationmark.triangle") {
                                Text("Not added").foregroundStyle(palette.error)
                            }
                        }
                        ForEach(model.wizardIssues, id: \.self) {
                            Text($0).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                        }
                        if let e = model.writeError { CoreFieldError(e) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: Space.s8 * 18)
                .scrollIndicators(.automatic)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The summary rows: every choice made, each with Change.
    private var reviewRows: [WizardReview.Row] {
        let names = chosen.map(\.name)
        let more = names.count > 3 ? " and \(names.count - 3) more" : ""
        var rows: [WizardReview.Row] = [
            .init(
                id: .code, symbol: "tray.full",
                label: "Code", value: names.isEmpty ? "No code" : ProjectItem.count(names.count, "repo"),
                sub: names.isEmpty ? nil : names.prefix(3).joined(separator: ", ") + more),
            .init(id: .kind, symbol: kind.symbol, label: "Kind", value: kind.title),
            .init(
                id: .brain, symbol: existingPlace ? "square.stack" : "plus.square", label: "Brain",
                value: existingPlace ? (place?.name ?? "Existing place") : "New place “\(name)”"),
        ]
        if kind.runs {
            rows.append(
                .init(
                    id: .runs, symbol: runner.symbol, label: kind == .app ? "Builds on" : "Runs on",
                    value: runner.title))
        }
        if kind.hasPublicLink {
            rows.append(
                .init(
                    id: .runs, symbol: publicLink ? "link" : "lock", label: "Link",
                    value: publicLink ? ProjectRules.host(slug) : "Private"))
        }
        return rows
    }

    private func repoRow(_ p: ProjectItem, _ r: RepoItem) -> some View {
        CoreRow(r.name, subtitle: rowLine(r), symbol: r.copy.isFailed ? "exclamationmark.triangle" : "tray.full") {
            switch r.copy {
            case .ready: Text("Ready").foregroundStyle(palette.success)
            case .fetching: Text("Copying…").foregroundStyle(palette.text2)
            case .unknown:
                Button("Fetch now") { model.fetchRepo(p, r) }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
            case .failed(let why, _):
                HStack(spacing: Space.s1) {
                    if why.needsConnection {
                        Button("Connect GitHub") { model.connectGithub() }
                            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    }
                    Button("Try again") { model.fetchRepo(p, r) }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
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

    // MARK: footer

    @ViewBuilder private var footer: some View {
        switch step {
        case .name:
            CoreDialogFooter(
                cancel: CoreAction("Cancel", key: .cancel, run: close),
                primary: CoreAction("Next", key: .primary) { go(.code) }, enabled: nameReady)
        case .code:
            CoreDialogFooter(
                cancel: CoreAction("Back") { go(.name) },
                primary: CoreAction("Next", key: .primary) { go(.kind) },
                alternate: needsGithub
                    ? CoreAction("Start with no code") {
                        noCode = true
                        go(.kind)
                    } : nil,
                enabled: !needsGithub)
        case .kind:
            CoreDialogFooter(
                cancel: CoreAction("Back") { go(.code) },
                primary: CoreAction("Next", key: .primary) { go(.brain) })
        case .brain:
            CoreDialogFooter(
                cancel: CoreAction("Back") { go(.kind) },
                primary: CoreAction("Next", key: .primary) { go(next(.brain)) })
        case .runs:
            CoreDialogFooter(
                cancel: CoreAction("Back") { go(.brain) },
                primary: CoreAction("Next", key: .primary) { go(.review) })
        case .review:
            if made == nil {
                CoreDialogFooter(
                    cancel: model.busy ? nil : CoreAction("Back") { go(previous(.review)) },
                    primary: CoreAction("Create project", key: .primary, run: create), busy: model.busy)
            } else {
                CoreDialogFooter(
                    cancel: nil,
                    primary: CoreAction("Open project", key: .primary) { model.openWizardProject() })
            }
        }
    }

    private func create() {
        guard nameReady, !model.busy else { return }
        Task {
            await model.create(
                name: name, slug: slug, colour: colour, repos: chosen, expose: kind.hasPublicLink ? publicLink : false,
                runner: kind.runs ? runner.rawValue : "auto",
                description: description.trimmingCharacters(in: .whitespaces), autoSuffix: !slugEdited, wizard: true,
                place: existingPlace ? place : nil, kind: kind)
        }
    }
}
