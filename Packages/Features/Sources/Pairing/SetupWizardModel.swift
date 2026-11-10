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
    static let installURL = "https://github.com/AinkradHQ/AinkradCore/releases/latest/download/get.sh"
    /// The oldest Core this app works with: the installer refuses anything older.
    static let minCoreVersion = "0.2.1"
    /// Never piped into `sudo`: that stops the installer at its first question (SIGTTIN) and Ctrl-C does nothing. `sh -c` with
    /// the script as an argument keeps the terminal for its questions.
    static let installCommand = "sudo AINKRAD_MIN_VERSION=\(minCoreVersion) sh -c \"$(curl -fsSL \(installURL))\""

    private(set) var stage: Stage = .choose
    /// What was pasted: the whole installer output is fine, the link is found in it.
    var linkText = "" {
        didSet {
            guard linkText != oldValue else { return }
            reparse()
        }
    }
    private var receivedLink: ConnectLink?
    /// The link came in through the `ainkrad://` scheme, not from the person's own paste: the screen says so and asks them to
    /// check the Core before going on.
    /// Computed, never stored and cleared: it holds exactly while the field means the link that came in. Editing it into
    /// something else (or into nothing) and back to the same link brings the warning back.
    var receivedFromApp: Bool { receivedLink != nil && link == receivedLink }

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
    /// Ignored while a claim is running: cancelling it after the Core answered would spend the one-time invite. Returns whether
    /// the link was taken.
    @discardableResult
    func receive(url: URL) -> Bool {
        guard stage != .connecting else { return false }
        linkText = url.absoluteString
        receivedLink = link
        stage = .connect
        return true
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
        scrub()
        installed = false
        stage = .choose
    }

    /// Forgets the link and its secret.
    private func scrub() {
        linkText = ""
        link = nil
        linkError = nil
        receivedLink = nil
    }

    private func claim(_ link: ConnectLink) async {
        do {
            _ = try await driver.claim(link.credential, endpoint: nil)
            let outcome = try await driver.awaitApproval()
            // A link pins the Core, so a pairing that still wants a check code did not get its pin from the link: trust nothing.
            guard outcome == .paired else {
                _ = try? await driver.cancel()
                scrub()
                stage = .failed(
                    Failure(
                        kind: .other(
                            "This Core did not confirm the identity in your link, so nothing was trusted. Start over with a fresh link."
                        )))
                return
            }
            scrub()
            onPaired()
        } catch is CancellationError {
        } catch { fail(error) }
    }

    private func fail(_ error: any Error) {
        var f = Failure.from(error)
        if f.kind == .badCode { f = Failure(kind: .badInvite) }
        // Nothing was sent (or the Core was never reached) only for these: the link stays for another try. Any other end
        // may have spent the invite, so the link and its secret go.
        switch f.kind {
        case .offline, .rateLimited, .clockSkew, .unproven, .oldApp: break
        default: scrub()
        }
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
