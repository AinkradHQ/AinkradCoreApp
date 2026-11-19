import AppKit
import Foundation
import Observation
import Shell

/// The part of setup that runs once the Core is connected (E3-1): About you, the AI account, Look and the Mac runner, over
/// the live desktop so a change of look shows behind the card. Every page can be skipped. Pure state; the views and the
/// Core calls are handed in.
@MainActor @Observable
final class SetupTourModel {
    enum Step: Int, CaseIterable {
        case role, stack, hours, style, life, ai, look, runner, ready

        /// The bar of seven (Welcome, Core, You, AI, Look, Runner, Ready) this page lights up to.
        var bar: Int {
            switch self {
            case .role, .stack, .hours, .style, .life: 2
            case .ai: 3
            case .look: 4
            case .runner: 5
            case .ready: 6
            }
        }
        var isYou: Bool { rawValue <= Step.life.rawValue }
    }

    /// A part of setup the welcome cards open before a Core is connected; it ends back on the welcome page.
    enum Detour { case you, look }

    /// The first Core version that has `PUT /brain/me/profile`. The coordinator renumbers it at integration.
    static let profileMinor = 95

    private(set) var step: Step?
    private(set) var detour: Detour?
    /// This Mac's own record of the name (the Home greeting); the name question writes to it.
    private let userProfile: UserProfile?
    var profile = SetupProfile()
    /// nil: nothing sent yet. true: the Core kept it. false: it could not (an older Core, or it was unreachable).
    private(set) var saved: Bool?
    private(set) var saving = false
    let macRunner: MacRunnerModel?
    /// How many AI accounts the Core holds (read by the AI page's host).
    var accountCount: () -> Int = { 0 }
    private let save: @MainActor ([SetupProfile.Item]) async -> Bool
    private let done: @MainActor () -> Void
    /// Whether the person came through the wizard of this launch: only then does the tour run.
    private(set) var pending = false

    init(
        macRunner: MacRunnerModel?, profile userProfile: UserProfile? = nil, save: @escaping @MainActor ([SetupProfile.Item]) async -> Bool,
        done: @escaping @MainActor () -> Void = {}
    ) {
        self.macRunner = macRunner
        self.userProfile = userProfile
        self.save = save
        self.done = done
    }

    var isActive: Bool { step != nil }

    /// The wizard paired a new Core: the tour starts once the desktop is open.
    func arm() { pending = true }

    /// Starts the tour when it is armed.
    func startIfArmed() {
        guard pending else { return }
        pending = false
        begin()
    }

    func begin() {
        if profile.name.isEmpty {
            profile.name = userProfile?.name.nilIfEmpty ?? NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        }
        step = .role
    }

    /// "About you" or "Your look" from the welcome page: just those pages, then back to the welcome page.
    func beginDetour(_ d: Detour) {
        begin()
        detour = d
        if d == .look { step = .look }
    }

    /// The pages that apply to this build: no runner page when the runner is not inside the app.
    private var order: [Step] {
        Step.allCases.filter { $0 != .runner || macRunner?.isAvailable == true }
    }

    /// No Back on the very first page of the tour; a detour always has one (it returns to the welcome page).
    var isFirst: Bool { detour == nil && step == order.first }

    func next() {
        guard let step, let i = order.firstIndex(of: step) else { return }
        if step == .role { userProfile?.set(profile.name) }
        if let detour {
            // Nothing is sent from a detour: there is no Core yet. The answers wait in `profile` for the tour.
            if (detour == .you && step == .life) || detour == .look { return endDetour() }
        } else if step == .life {
            sendProfile()
        }
        if i + 1 < order.count { self.step = order[i + 1] } else { finish() }
    }

    func back() {
        guard let step, let i = order.firstIndex(of: step) else { return }
        if detour != nil, i == 0 || step == .look { return endDetour() }
        if i > 0 { self.step = order[i - 1] }
    }

    private func endDetour() {
        detour = nil
        step = nil
    }

    func finish() {
        step = nil
        detour = nil
        done()
    }

    /// The About you answers go to the Core once, on leaving the last About you page. Nothing answered sends nothing.
    func sendProfile() {
        let items = profile.items
        guard !items.isEmpty, !saving else { return }
        saving = true
        Task {
            let ok = await save(items)
            saved = ok
            saving = false
        }
    }

    /// The Ready page's line for About you.
    var aboutLine: String {
        if profile.items.isEmpty { return "Skipped for now" }
        switch saved {
        case true?: return "Saved to your Brain"
        case false?: return "Could not be saved yet"
        case nil: return saving ? "Saving…" : "Skipped for now"
        }
    }

    var aiLine: String {
        let n = accountCount()
        return n == 0 ? "Skipped for now" : n == 1 ? "1 connected" : "\(n) connected"
    }

    var runnerLine: String {
        macRunner?.isAvailable == true ? (macRunner?.useThisMac == true ? "Runner is on" : "Runner is off") : "Not in this build"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
