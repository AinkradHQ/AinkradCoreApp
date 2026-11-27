import Foundation

/// The steps of the New Project wizard: what it is and its name, the code, then the review (Brain place, runner, link).
enum WizardStep: Int, CaseIterable {
    case what = 1
    case code, review

    var title: String {
        switch self {
        case .what: "What & name"
        case .code: "Code"
        case .review: "Review"
        }
    }
}

/// A row of the review that opens its choice in place (kind and code go back to their own step).
enum WizardRow: String, CaseIterable, Identifiable {
    case kind, code, brain, runs, link
    var id: String { rawValue }
}

/// The kind the repos corrected, for the Code step's one line "Looks like an App: Swift, iOS · Change · Undo".
struct KindCorrection: Equatable {
    var from: ProjectKind
    var to: ProjectKind
    var evidence: String
    var line: String { "Looks like \(to.lookWord): \(evidence)" }
}

/// Everything the person has typed and picked in the wizard. The wizard edits one of these, and the model keeps it when
/// the dialog closes, so reopening New Project picks up where it stopped (W-5, W-6).
struct WizardDraft {
    var step = WizardStep.what
    var name = ""
    var description = ""
    /// The link name once the person edits it; until then it follows the name.
    var slugText = ""
    var slugEdited = false
    var colour = ProjectColour.standard(for: "")
    /// The colour once the person picks one; until then it follows the name.
    var colourPicked = false
    var picked: Set<String> = []
    var pasted: [PickRepo] = []
    var runner = WizardRunner.auto
    /// The existing Brain place to link; nil makes a new one named after the project.
    var place: BrainPlace?
    var existingPlace = false
    var publicLink = false
    var kind = ProjectKind.web
    /// The person chose the kind: the repos stop correcting it.
    var kindPicked = false
    var corrected: KindCorrection?
    /// "Anything else" skips the Code step; opening it (Change on the review) makes it part of the way.
    var wantsCode = false
    /// "Start with no code": the Code step is passed with nothing picked.
    var noCode = false
    var moreOptions = false

    init(name: String = "", picked: Set<String> = [], pasted: [PickRepo] = [], kind: ProjectKind? = nil) {
        self.name = name
        self.pasted = pasted
        self.picked = picked.union(pasted.map(\.id))
        colour = .standard(for: ProjectRules.slug(from: name))
        if let kind {
            self.kind = kind
            kindPicked = true
        }
    }

    var slug: String { slugEdited ? slugText : ProjectRules.slug(from: name) }
    var nameProblem: String? { name.isEmpty ? nil : ProjectRules.nameProblem(name) }
    var slugProblem: String? { name.isEmpty ? nil : ProjectRules.slugProblem(slug) }
    var nameReady: Bool { ProjectRules.nameProblem(name) == nil && ProjectRules.slugProblem(slug) == nil }
    /// Why Next waits, in words; nil when it does not.
    var whyNotNext: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give it a name to continue." }
        return ProjectRules.nameProblem(name) ?? ProjectRules.slugProblem(slug)
    }
    /// Worth keeping when the dialog closes.
    var hasContent: Bool { !name.isEmpty || !picked.isEmpty }

    /// The steps on the way: a project that is not software skips the code unless the person asked for it.
    var steps: [WizardStep] { WizardStep.allCases.filter { $0 != .code || kind != .other || wantsCode } }
    func next(_ s: WizardStep) -> WizardStep { steps.first { $0.rawValue > s.rawValue } ?? .review }
    func previous(_ s: WizardStep) -> WizardStep { steps.last { $0.rawValue < s.rawValue } ?? .what }

    mutating func pickKind(_ k: ProjectKind) {
        kind = k
        kindPicked = true
        corrected = nil
    }

    /// The repos say what it is: the kind follows them until the person chooses one. Nothing clear, nothing changes (and a
    /// correction the repos no longer back goes away).
    mutating func follow(_ s: KindSuggestion, hasRepos: Bool) {
        guard !kindPicked else { return }
        guard hasRepos, s.clear else {
            if let c = corrected {
                kind = c.from
                corrected = nil
            }
            return
        }
        guard s.kind != kind else {
            corrected?.evidence = s.evidence
            return
        }
        let from = corrected?.from ?? kind
        kind = s.kind
        corrected = from == kind ? nil : KindCorrection(from: from, to: kind, evidence: s.evidence)
    }

    /// "Undo" on the correction line: back to what it was, and the repos stop deciding.
    mutating func undoCorrection() {
        guard let c = corrected else { return }
        kind = c.from
        kindPicked = true
        corrected = nil
    }
}

extension WizardDraft {
    /// The review's rows: every choice made, one row each, whatever the kind (no two share an id).
    func reviewItems(repoNames names: [String], brainOn: Bool) -> [WizardReviewItem] {
        let more = names.count > 3 ? " and \(names.count - 3) more" : ""
        var rows: [WizardReviewItem] = [
            .init(id: .kind, symbol: kind.symbol, label: "Kind", value: kind.title),
            .init(
                id: .code, symbol: "tray.full", label: "Code",
                value: names.isEmpty ? "No code" : ProjectItem.count(names.count, "repo"),
                sub: names.isEmpty ? nil : names.prefix(3).joined(separator: ", ") + more),
            .init(
                id: .brain, symbol: existingPlace ? "square.stack" : "plus.square", label: "Brain",
                value: !brainOn
                    ? "No Brain on this Core"
                    : existingPlace ? (place?.name ?? "Existing place") : "New place “\(name)”",
                changeable: brainOn),
        ]
        if kind.runs {
            rows.append(
                .init(
                    id: .runs, symbol: runner.symbol, label: kind == .app ? "Builds on" : "Runs on", value: runner.title
                ))
        }
        if kind.hasPublicLink {
            rows.append(
                .init(
                    id: .link, symbol: publicLink ? "link" : "lock", label: "Link",
                    value: publicLink ? ProjectRules.host(slug) : "Private"))
        }
        return rows
    }
}
