import CoreKit
import Foundation
import Observation

/// The first-run wizard: set up a new Core or use an existing one, then paste the connect link and claim it.
/// Claiming is `DevicePairing`'s (the link is an invite credential and carries the Core fingerprint, so the Core must prove
/// itself before anything is sent); this model only walks the person there and says what went wrong in plain words.
@MainActor @Observable
final class SetupWizardModel {
    enum Stage: Equatable {
        /// "Set up a new Core" or "Use an existing Core".
        case choose
        /// The one command to run on a Linux machine.
        case install
        /// Paste the link the installer printed.
        case connect
        case connecting
        case failed(Failure)
    }

    /// The one line the Core's installer is run with: the hosted bootstrap is a GitHub release asset.
    static let installCommand =
        "curl -fsSL https://github.com/AinkradHQ/AinkradCore/releases/latest/download/get.sh | sudo sh"

    private(set) var stage: Stage = .choose
    /// What was pasted: the whole installer output is fine, the link is found in it.
    var linkText = "" { didSet { if linkText != oldValue { reparse() } } }
    /// The link in `linkText` once it parses; the screen shows its address and fingerprint before anything is sent.
    private(set) var link: ConnectLink?
    /// Why `linkText` is not a link yet. Not shown until something has been typed.
    private(set) var linkError: String?

    private let driver: any PairingDriver
    private let onPaired: @MainActor () -> Void
    private var task: Task<Void, Never>?

    init(driver: any PairingDriver, onPaired: @escaping @MainActor () -> Void) {
        self.driver = driver
        self.onPaired = onPaired
    }

    func chooseNew() {
        installed = true
        stage = .install
    }
    func chooseExisting() {
        installed = false
        stage = .connect
    }
    func haveLink() { stage = .connect }
    func back() {
        task?.cancel()
        stage = stage == .connect && installed ? .install : .choose
    }
    /// Whether the person came through the install screen (Back goes there instead of the first screen).
    private var installed = false

    /// The `ainkrad://connect` URL was opened (a link clicked, or handed over by the system): fill it in and show it, but wait
    /// for the person to press Connect.
    func receive(url: URL) {
        task?.cancel()
        linkText = url.absoluteString
        stage = .connect
    }

    var canConnect: Bool { link != nil && stage != .connecting }

    func connect() {
        guard let link, stage != .connecting else { return }
        stage = .connecting
        task?.cancel()
        task = Task { [weak self] in await self?.claim(link) }
    }

    /// Back to the paste screen with the same text, for a failure the person can retry.
    func tryAgain() { stage = .connect }

    /// Back to the very first screen, nothing kept (after a Core that was not the expected one).
    func startOver() {
        task?.cancel()
        linkText = ""
        installed = false
        stage = .choose
    }

    private func claim(_ link: ConnectLink) async {
        do {
            _ = try await driver.claim(link.credential, endpoint: nil)
            var outcome = try await driver.awaitApproval()
            // A link pins the Core, so there is no check code to compare; this only guards a driver that asks anyway.
            if outcome == .awaitingConfirmation {
                try await driver.confirmSAS()
                outcome = try await driver.awaitApproval()
            }
            if outcome == .paired { onPaired() }
        } catch is CancellationError {
        } catch { fail(error) }
    }

    private func fail(_ error: any Error) {
        var f = Failure.from(error)
        if f.kind == .badCode { f = Failure(kind: .badInvite) }
        stage = .failed(f)
    }

    private func reparse() {
        link = nil
        linkError = nil
        let t = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        do { link = try ConnectLink.parse(ConnectLink.find(in: t) ?? t) } catch {
            linkError = error.localizedDescription
        }
    }
}

#if DEBUG
extension SetupWizardModel {
    /// Snapshot scenes: set the screen without a Core.
    func debugSet(_ stage: Stage, link: String = "") {
        linkText = link
        self.stage = stage
    }
}
#endif
