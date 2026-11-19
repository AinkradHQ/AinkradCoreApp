import AppKit
import CoreKit
import Foundation
import Observation
import Shell

/// The first-run wizard: set up a new Core or use an existing one, then paste the connect link and claim it.
/// Claiming is `DevicePairing`'s (the link is an invite credential and carries the Core fingerprint, so the Core must prove
/// itself before anything is sent); this model only walks the person there and says what went wrong in plain words.
@MainActor @Observable
final class SetupWizardModel {
    enum Stage: Equatable {
        /// "Set up a new Core" or "Use an existing Core".
        case choose
        /// The one command to run on a Linux machine, with this install's code in it.
        case install
        /// The command was pasted: waiting for the Core's installer to leave the link (or for the person to paste it).
        case waiting
        /// The installer's link arrived: its Core is shown, and the person presses Connect.
        case found
        /// "Use an existing Core": the Cores this network advertises, and the paste screen as the way on.
        case nearby
        /// Paste the link the installer printed.
        case connect
        case connecting
        case failed(Failure)
    }

    /// The one line the Core's installer is run with: the hosted bootstrap is a GitHub release asset.
    static let installURL = "https://github.com/AinkradHQ/AinkradCore/releases/latest/download/get.sh"
    /// The oldest Core this app works with: the installer refuses anything older.
    static let minCoreVersion = "0.2.1"
    /// The command with this install's code and key in it (`AINKRAD_RENDEZVOUS`), so the installer can hand the link back by
    /// itself. The code is single use and is never printed again by the installer's re-run command.
    static func installCommand(rendezvous spec: String) -> String {
        installCommand.replacingOccurrences(
            of: "AINKRAD_MIN_VERSION=\(minCoreVersion) ", with: "AINKRAD_MIN_VERSION=\(minCoreVersion) AINKRAD_RENDEZVOUS=\(spec) ")
    }

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
    /// Called once a new Core is paired, just before the desktop opens: the setup tour (About you, AI, Look, runner) starts there.
    var armTour: @MainActor () -> Void = {}
    /// The first screen's hero has been left: Get started was pressed (or a link came in).
    private(set) var welcomed = false
    private var task: Task<Void, Never>?

    /// This install's code and key; made when the person chooses "Set up a new Core" and dropped when they leave.
    private(set) var rendezvous: RendezvousSession?
    private let rendezvousClient: any RendezvousClient
    private var waiter: Task<Void, Never>?
    /// The wait ran out (15 minutes) or the code was used: the screen says so and points at the paste screen.
    private(set) var waitEnded: String?
    /// Cores this network advertises, for "Use an existing Core".
    private(set) var nearby: [NearbyCore] = []
    private let discovery: any CoreDiscovery
    /// The Core the person picked from the list: a pasted link must be for this one.
    private(set) var picked: NearbyCore?
    /// How often the rendezvous is asked, and how long to wait in all; a test makes them small.
    var pollEvery: Duration = .seconds(2)
    var waitFor: Duration = .seconds(15 * 60)

    init(
        driver: any PairingDriver, rendezvous: any RendezvousClient = LiveRendezvous(),
        discovery: any CoreDiscovery = NoDiscovery(), onPaired: @escaping @MainActor () -> Void
    ) {
        self.driver = driver
        self.rendezvousClient = rendezvous
        self.discovery = discovery
        self.onPaired = onPaired
    }

    func getStarted() { welcomed = true }

    func chooseNew() {
        installed = true
        picked = nil
        if rendezvous == nil { rendezvous = RendezvousSession() }
        stage = .install
    }
    func chooseExisting() {
        installed = false
        stage = .nearby
        discovery.start { [weak self] in self?.nearby = $0 }
    }

    /// A Core from the list: the paste screen follows, and only that Core's link is taken.
    func pick(_ core: NearbyCore) {
        picked = core
        discovery.stop()
        stage = .connect
    }

    /// "Paste a link instead" (or "I have the link"): the paste screen, whatever was found.
    func haveLink() {
        stopWaiting()
        discovery.stop()
        stage = .connect
    }

    func back() {
        task?.cancel()
        switch stage {
        case .waiting, .found:
            stopWaiting()
            scrub()
            stage = .install
        case .connect where picked != nil:
            picked = nil
            chooseExisting()
        case .connect where installed: stage = .install
        case .nearby:
            discovery.stop()
            stage = .choose
        default: stage = .choose
        }
    }

    /// "I pasted it": waits for the installer to leave the link, asking the rendezvous every couple of seconds.
    func startWaiting() {
        guard let session = rendezvous else { return haveLink() }
        waitEnded = nil
        stage = .waiting
        waiter?.cancel()
        waiter = Task { [weak self, rendezvousClient, pollEvery, waitFor] in
            let clock = ContinuousClock()
            let deadline = clock.now + waitFor
            while !Task.isCancelled {
                do {
                    if let m = try await rendezvousClient.fetch(id: session.id) {
                        if let text = session.open(epk: m.epk, ct: m.ct) { self?.arrived(text) } else {
                            self?.waitEnded = "A message came, but it was not for this setup. Paste the link instead."
                        }
                        return
                    }
                } catch RendezvousError.used {
                    self?.waitEnded = "This setup code was used already. Start again, or paste the link."
                    return
                } catch is CancellationError {
                    return
                } catch {}
                if clock.now >= deadline {
                    self?.waitEnded = "Nothing arrived. Check the line was pasted in full, or paste the link instead."
                    return
                }
                try? await Task.sleep(for: pollEvery)
            }
        }
    }

    private func stopWaiting() {
        waiter?.cancel()
        waiter = nil
    }

    /// The installer's link came through the rendezvous: shown for the person to check, never connected by itself.
    private func arrived(_ text: String) {
        linkText = text
        guard link != nil, stage == .waiting else {
            linkText = ""
            waitEnded = "The link that arrived could not be read. Paste it instead."
            return
        }
        stage = .found
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
        welcomed = true
        linkText = url.absoluteString
        receivedLink = link
        stage = .connect
        return true
    }

    var canConnect: Bool { link != nil && stage != .connecting && !pickedMismatch }

    /// A Core was picked from the list and the link pasted is for another one: nothing is sent to it.
    var pickedMismatch: Bool { picked.map { link != nil && link?.coreFingerprint != $0.fingerprint } ?? false }

    func connect() {
        guard let link, stage != .connecting, !pickedMismatch else { return }
        stage = .connecting
        task?.cancel()
        task = Task { [weak self] in await self?.claim(link) }
    }

    /// Back to the paste screen with the same text, for a failure the person can retry.
    func tryAgain() {
        stopWaiting()
        stage = .connect
    }

    /// Back to the very first screen, nothing kept (after a Core that was not the expected one).
    func startOver() {
        task?.cancel()
        stopWaiting()
        discovery.stop()
        scrub()
        rendezvous = nil
        picked = nil
        installed = false
        welcomed = false
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
            finishSetup()
        } catch is CancellationError {
        } catch { fail(error) }
    }

    /// Paired: the desktop opens, with the setup tour over it (its first question is the name).
    func finishSetup() {
        stopWaiting()
        rendezvous = nil
        armTour()
        onPaired()
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
