import Foundation
import Observation

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

    /// The first Core version that has `PUT /brain/me/profile`. The coordinator renumbers it at integration.
    static let profileMinor = 95

    private(set) var step: Step?
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
        macRunner: MacRunnerModel?, save: @escaping @MainActor ([SetupProfile.Item]) async -> Bool,
        done: @escaping @MainActor () -> Void = {}
    ) {
        self.macRunner = macRunner
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
        step = .role
    }

    func begin() { step = .role }

    /// The pages that apply to this build: no runner page when the runner is not inside the app.
    private var order: [Step] {
        Step.allCases.filter { $0 != .runner || macRunner?.isAvailable == true }
    }

    var isFirst: Bool { step == order.first }

    func next() {
        guard let step, let i = order.firstIndex(of: step) else { return }
        if step == .life { sendProfile() }
        if i + 1 < order.count { self.step = order[i + 1] } else { finish() }
    }

    func back() {
        guard let step, let i = order.firstIndex(of: step), i > 0 else { return }
        self.step = order[i - 1]
    }

    func finish() {
        step = nil
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
