import CoreUI
import SwiftUI

/// The one prominent action of a project's space, which follows where the project stands:
/// Add Repos… → Set Up… → Set Secrets… → Start → Open. A project that is not software has New Doc…; an archived one Unarchive.
/// Pure on purpose: the top bar and the tests read the same table.
struct MainAction: Equatable {
    enum Kind: Equatable {
        case addRepos, reviewRepos, waiting, setUp, setSecrets, start, starting, open, runAgain, openServices, newDoc, unarchive
    }
    var kind: Kind
    var title: String
    var symbol: String
    /// The action is under way (setting up, starting): the button shows its words and cannot be pressed.
    var busy = false
}

extension ProjectItem {
    /// `starting`: a Start of this project is in flight (the Core has not said "starting" yet).
    /// `view`: the kind the stage shows when the project has several (web + app); the action follows it.
    func mainAction(starting: Bool = false, view: ProjectKind? = nil) -> MainAction {
        let kind = view ?? self.kind
        if archived { return MainAction(kind: .unarchive, title: "Unarchive", symbol: "arrow.uturn.backward") }
        if kind == .other { return MainAction(kind: .newDoc, title: "New Doc…", symbol: "square.and.pencil") }
        let start = MainAction(
            kind: .start,
            title: tag == .failed
                ? (kind == .app ? "Build Again" : "Start Again") : kind == .app ? "Build and Run" : "Start",
            symbol: "play")
        let busyStart = MainAction(
            kind: .starting, title: kind == .app ? "Building…" : "Starting…", symbol: "play", busy: true)
        switch setup {
        case .noRepos: return MainAction(kind: .addRepos, title: "Add Repos…", symbol: "plus")
        case .copying, .checking:
            return MainAction(kind: .waiting, title: "Setting Up…", symbol: "gearshape", busy: true)
        case .copyFailed: return MainAction(kind: .reviewRepos, title: "Review Repos…", symbol: "arrow.triangle.branch")
        case .needsSetup: return MainAction(kind: .setUp, title: "Set Up…", symbol: "wand.and.stars")
        case .ready(let d) where !d.secrets.isEmpty:
            return MainAction(kind: .setSecrets, title: "Set Secrets…", symbol: "key")
        case .ready: return starting ? busyStart : start
        case .ran:
            switch run?.state ?? .stopped {
            case .running:
                switch kind {
                case .app: return MainAction(kind: .runAgain, title: "Run Again", symbol: "play")
                case .infra: return MainAction(kind: .openServices, title: "Open Services", symbol: "server.rack")
                default: return MainAction(kind: .open, title: "Open", symbol: "arrow.up.forward.square")
                }
            case .starting: return busyStart
            case .stopped, .failed: return starting ? busyStart : start
            }
        }
    }

    /// The secret a failure is about: one the setup is missing whose name the failure says. Never a guess from the draft alone.
    var failedSecret: String? {
        let said = ([live?.failure, live?.failureFix] + (live?.steps.map(\.detail) ?? [])).compactMap { $0 }
            .joined(separator: " ").lowercased()
        return draft?.secrets.first { said.contains($0.lowercased()) }
    }

    /// The word of the state in the top bar. It is always the state, never the link: a crashed or unknown project must not
    /// read as running. A project that is not software has no state, only when it was last edited.
    func spaceBadge(now: Date) -> (label: String, tone: Tone, symbol: String) {
        if archived { return ("Archived", .queue, "archivebox") }
        if allKinds == [.other] { return ("Edited \(runsAgo(updatedAt, now: now))", .queue, "doc.text") }
        if crash != nil, !stale { return ("Crashed", .fail, "exclamationmark.triangle") }
        if stale, tag == .running || tag == .starting { return ("Status unknown", .queue, "questionmark.circle") }
        if run == nil {
            switch setup {
            case .ready(let d):
                return d.secrets.isEmpty
                    ? ("Ready to start", .queue, "play.circle") : ("Needs secrets", .warn, "key")
            case .needsSetup: return ("Needs setup", .warn, "wand.and.stars")
            case .copying, .checking: return ("Setting up", .warn, "gearshape")
            default: break
            }
        }
        if tag == .new { return ("No repos yet", .queue, "sparkle") }
        return badge
    }

    /// Why Stop and Restart cannot be pressed (the Core is not answering, or this device cannot change); nil when they can.
    func controlBlock(canControl: Bool) -> String? {
        if stale { return "The Core is not answering. This will work again once it is back." }
        return canControl ? nil : "Not available while this device cannot change projects or the Core is unreachable"
    }
}

/// The state word in the top bar. The word crossfades when the state changes; a starting project breathes in opacity, which
/// stays when Reduce Motion is on (the Mac of the owner has it on, so a frozen badge would read as disabled).
struct SpaceStateBadge: View {
    let project: ProjectItem
    let now: Date
    var body: some View {
        let b = project.spaceBadge(now: now)
        StateBadge(b.label, tone: b.tone, symbol: b.symbol)
            .id(b.label)
            .transition(.opacity)
            .animation(Motion.out(Motion.ui), value: b.label)
            .coreBreathing(project.tag == .starting && !project.archived && project.kind != .other)
            .accessibilityLabel("State: \(b.label)")
    }
}

/// Set once by the space on its first appearance: pages read it so their islands rise on the first entry only, and a switch
/// between pages is a plain fade.
private struct SpaceSettledKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var spaceSettled: Bool {
        get { self[SpaceSettledKey.self] }
        set { self[SpaceSettledKey.self] = newValue }
    }
}
