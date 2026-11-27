import AppKit
import CoreUI
import SwiftUI

/// Project Settings: two equal columns of cards, each row as tall as its taller card. Name and colour, where it runs by default
/// (CPU, memory and idle stop are one Save, so one Touch ID), what it is, the public link, keeping copies fresh and Archive
/// (a few seconds to undo). The Core has no permanent delete, so there is none here. The link name cannot change while the project
/// runs. TODO(design-system): proposal CoreSwatch for the colour row.
struct SettingsPage: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var name: String
    @State private var description: String
    @State private var slug: String
    @State private var settled = false
    @State private var insights: ProjectInsightsModel
    /// CPU, memory and idle stop as edited and not saved yet; nil while they match the Core.
    @State private var limitsDraft: ProjectLimits?

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _insights = State(initialValue: ProjectInsightsModel(model: model, project: project))
        _name = State(initialValue: project.name)
        _description = State(initialValue: project.description)
        _slug = State(initialValue: project.slug)
        #if DEBUG
        _limitsDraft = State(initialValue: model.demoLimitsDraft)
        #endif
    }

    private var changed: Bool {
        name.trimmingCharacters(in: .whitespaces) != project.name || description != project.description
            || slug != project.slug
    }
    /// The Core refuses a new link name while the project runs.
    private var linkLocked: Bool { project.tag == .running || project.tag == .starting }
    private var nameProblem: String? { ProjectRules.nameProblem(name) }
    private var slugProblem: String? { slug == project.slug ? nil : ProjectRules.slugProblem(slug) }

    /// The cards in reading order; they pair up two to a row.
    private var cards: [AnyView] {
        var out = [AnyView(general)]
        if project.kind.runs { out.append(AnyView(limits)) }
        out.append(AnyView(KindSettings(model: model, project: project)))
        if project.kind.hasPublicLink { out.append(AnyView(publicLink)) }
        if insights.supported { out.append(AnyView(keepFresh)) }
        out.append(AnyView(archiveCard))
        return out
    }

    var body: some View {
        let rows = stride(from: 0, to: cards.count, by: 2).map { Array(cards[$0..<min($0 + 2, cards.count)]) }
        ScrollView {
            VStack(spacing: Space.s2) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: Space.s2) {
                        ForEach(rows[i].indices, id: \.self) { rows[i][$0] }
                        if rows[i].count == 1 { Color.clear.frame(maxWidth: .infinity) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .coreRise(settled, i)
                }
            }
        }
        .onAppear { settled = true }
        .task(id: project.id) { await insights.loadTuning() }
        // Edited elsewhere (another Mac, the Core): a field the person has not touched follows it, so it never looks unsaved.
        .onChange(of: project.name) { old, new in if name == old { name = new } }
        .onChange(of: project.description) { old, new in if description == old { description = new } }
        .onChange(of: project.slug) { old, new in if slug == old { slug = new } }
        .task { await model.loadRunners() }
        .accessibilityIdentifier("project-page-Project Settings")
    }

    // MARK: General

    private var general: some View {
        Island("Name and colour", sub: origin) {
            VStack(alignment: .leading, spacing: Space.s4) {
                CoreTextField(
                    "Name", placeholder: "Project name", text: $name, error: changed ? nameProblem : nil, onSubmit: save
                )
                CoreTextField("Description", placeholder: "What it is, in a line", text: $description, onSubmit: save)
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreTextField(
                        "Link name", placeholder: "atlas-notes", text: $slug, error: slugProblem, onSubmit: save
                    )
                    .disabled(model.readOnly || linkLocked)
                    .help(linkLocked ? "Stop the project to change its link name." : "")
                    Text(
                        linkLocked
                            ? "Stop the project to change its link name."
                            : project.kind.hasPublicLink
                                ? "Public link: \(ProjectRules.host(slug)). It can change while the project is stopped and holds no secrets."
                                : "The link name is how the Core knows this project. It can change while the project is stopped."
                    )
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreFieldLabel("Colour")
                    ColourSwatches(
                        selection: Binding(
                            get: { model.colour(project) }, set: { model.setColour($0, for: project) }),
                        compact: true)
                }
                if let e = model.writeError { CoreFieldError(e) }
                if changed {
                    HStack(spacing: Space.s2) {
                        Spacer(minLength: 0)
                        Button("Revert") {
                            name = project.name
                            description = project.description
                            slug = project.slug
                            model.clearWriteError()
                        }
                        .buttonStyle(CoreButtonStyle(.secondary))
                        Button("Save") { save() }
                            .buttonStyle(CoreButtonStyle(.prominent, busy: model.busy))
                            .disabled(nameProblem != nil || slugProblem != nil || model.busy || model.readOnly)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .onChange(of: name) { _, _ in model.clearWriteError() }
    }

    private func save() {
        guard changed, nameProblem == nil, slugProblem == nil, !model.busy else { return }
        Task { await model.saveGeneral(project, name: name, description: description, slug: slug) }
    }

    /// "Made by hand · created 12 Nov 2026" or "Made from GitHub · …".
    private var origin: String {
        let how = project.source == "github" ? "Made from GitHub" : "Made by hand"
        guard let at = project.createdAt else { return how }
        return "\(how) · created \(at.formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: Public link

    /// The switch, one line of words and the link with Copy, as the mockup's card.
    private var publicLink: some View {
        Island(
            title: "Public link",
            accessory: {
                CoreSwitch(
                    "",
                    isOn: Binding(
                        get: { project.expose }, set: { on in Task { await model.setExpose(project, on) } })
                )
                .disabled(model.readOnly || pending).accessibilityLabel("Public link")
                .help(
                    model.readOnly ? "This device can look at projects but not change them." : pending ? "Saving…" : "")
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Anyone with the link can see the project page, not your code.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s2) {
                    Text(project.link).font(.system(size: MacTextSize.body, design: .monospaced)).lineLimit(1)
                    Spacer(minLength: 0)
                    CoreIconButton(symbol: "doc.on.doc", label: "Copy the link") { model.copyLink(project) }
                        .disabled(!project.expose || pending)
                        .help(project.expose ? "Copy the link" : "Turn the public link on to share it")
                }
                .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                .coreCard(GlassInk.well, radius: Radius.row)
                .opacity(project.expose ? 1 : 0.45)
            }
        }
    }

    private var pending: Bool { model.exposing.contains(project.id) }

    // MARK: Keep copies fresh

    /// How often the Core fetches the repos by itself (the Core's own setting, per project).
    private var keepFresh: some View {
        Island("Keep copies fresh") {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreSelect(
                    "Fetch new changes",
                    selection: Binding(
                        get: { insights.tuning.fetchInterval },
                        set: { v in Task { await insights.set(fetchInterval: v) } }),
                    options: FetchInterval.options.map { CoreSelectOption($0.minutes, $0.title) }
                )
                .disabled(model.readOnly || !insights.tuningLoaded)
                Text("The Core copies each repo by itself; Fetch Now on the Code page does it at once.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Run limits

    private var limits: some View {
        Island("Where it runs by default") {
            VStack(alignment: .leading, spacing: Space.s6) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.s5, verticalSpacing: Space.s3) {
                    GridRow {
                        label("Runs on")
                        runnerChoice
                    }
                    if insights.supported, !insights.environments.isEmpty {
                        GridRow {
                            label("Default environment")
                            CoreSelect(
                                nil,
                                selection: Binding(
                                    get: { insights.tuning.defaultEnvironment ?? insights.environments[0] },
                                    set: { v in Task { await insights.set(defaultEnvironment: v) } }),
                                options: insights.environments.map { CoreSelectOption($0, $0) }
                            )
                            .disabled(model.readOnly).frame(width: Space.s8 * 5)
                        }
                    }
                    GridRow {
                        label("CPU")
                        limitSelect(
                            ProjectsOptions.coreChoice(limitsNow),
                            ProjectsOptions.cores.map { CoreSelectOption($0, $0 == 1 ? "1 core" : "\($0) cores") }
                        ) { n in
                            var l = limitsNow
                            l.cpus = Double(n)
                            return l
                        }
                    }
                    GridRow {
                        label("Memory")
                        limitSelect(
                            ProjectsOptions.memoryChoice(limitsNow),
                            ProjectsOptions.memoryGB.map { CoreSelectOption($0, "\($0) GB") }
                        ) { g in
                            var l = limitsNow
                            l.memoryMb = Int64(g) * 1024
                            return l
                        }
                    }
                    GridRow {
                        label("Idle stop")
                        HStack(spacing: Space.s2) {
                            limitSelect(
                                ProjectsOptions.idleChoice(limitsNow),
                                ProjectsOptions.idleChoices.map { CoreSelectOption($0.minutes, $0.title) }
                            ) { m in ProjectsOptions.setIdle(limitsNow, minutes: m) }
                            if let idle = project.live?.idle, project.tag == .running {
                                Text("· \(idle)").foregroundStyle(GlassInk.secondary).monospacedDigit()
                            }
                        }
                    }
                }
                if let draft = limitsDraft, draft != project.limits {
                    HStack(spacing: Space.s2) {
                        Spacer(minLength: 0)
                        Button("Revert") { limitsDraft = nil }.buttonStyle(CoreButtonStyle(.secondary))
                        Button("Save") {
                            Task {
                                await model.setLimits(project, draft)
                                limitsDraft = nil
                            }
                        }
                        .buttonStyle(CoreButtonStyle(.prominent, busy: model.busy))
                        .disabled(model.busy || model.readOnly)
                        .help("Saves CPU, memory and idle stop together, with one Touch ID")
                    }
                    .transition(.opacity)
                }
            }
            .animation(Motion.out(Motion.ui), value: limitsDraft != nil && limitsDraft != project.limits)
        }
        .onChange(of: project.limits) { _, new in if limitsDraft == new { limitsDraft = nil } }
    }

    /// CPU, memory and idle stop as the page shows them: the edit in hand, else what the Core holds.
    private var limitsNow: ProjectLimits { limitsDraft ?? project.limits }

    /// One of this project's own limits: it joins the edit in hand, which Save sends as one change.
    private func limitSelect(
        _ current: Int, _ options: [CoreSelectOption<Int>], _ make: @escaping (Int) -> ProjectLimits
    ) -> some View {
        CoreSelect(nil, selection: Binding(get: { current }, set: { v in limitsDraft = make(v) }), options: options)
            .disabled(model.readOnly || model.busy).frame(width: Space.s8 * 5)
    }

    /// Where the project prefers to run, with what the Core has paired (Mac runners serve This Mac, Linux ones Home server).
    @ViewBuilder private var runnerChoice: some View {
        if model.runnerSupported {
            VStack(alignment: .leading, spacing: Space.s1) {
                CoreSelect(
                    nil,
                    selection: Binding(
                        get: { WizardRunner(rawValue: project.runner) ?? .auto },
                        set: { r in Task { await model.setRunner(project, r.rawValue) } }),
                    options: WizardRunner.allCases.map { CoreSelectOption($0, $0.title) }
                )
                .disabled(model.readOnly || model.busy).frame(width: Space.s8 * 5)
                Text((WizardRunner(rawValue: project.runner) ?? .auto).line(model.runners))
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(model.coreName).help("This Core keeps one place for now. Update it to choose where projects run.")
        }
    }

    // MARK: Archive

    /// Archive this project: it leaves the list, its run stops, and the toast offers Undo for a few seconds. A Core without
    /// the unarchive route (older than minor 95) asks first instead, since it cannot undo. The Core has no permanent delete.
    private var archiveCard: some View {
        Island("Archive this project") {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(
                    model.insightsService == nil
                        ? "Takes it off the list after one question and stops its run. Repos, secrets and the Brain room are kept, and your repos stay on GitHub. This Core cannot bring it back from here."
                        : "Takes it off the list and stops its run. Repos, secrets and the Brain room are kept, your repos stay on GitHub, and you can undo for a few seconds."
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                Button {
                    if model.insightsService == nil {
                        model.confirmArchive(project)
                    } else {
                        Task { await model.archive(project) }
                    }
                } label: {
                    Label("Archive Project", systemImage: "archivebox")
                }
                .buttonStyle(CoreButtonStyle(.secondary)).disabled(model.readOnly || model.busy)
                .accessibilityIdentifier("project-archive")
            }
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).foregroundStyle(GlassInk.secondary).gridColumnAlignment(.leading)
    }

    /// "2 CPUs", "1.5 CPUs", "1 CPU".
    static func cpus(_ n: Double) -> String {
        let t = n == n.rounded() ? String(Int(n)) : String(n)
        return "\(t) CPU\(n == 1 ? "" : "s")"
    }

    /// "2 GB", "512 MB".
    static func memory(_ mb: Int64) -> String {
        guard mb >= 1024 else { return "\(mb) MB" }
        let gb = Double(mb) / 1024
        return gb == gb.rounded() ? "\(Int(gb)) GB" : String(format: "%.1f GB", gb)
    }
}
