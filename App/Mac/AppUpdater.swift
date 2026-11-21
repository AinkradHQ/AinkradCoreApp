import AppKit
import CoreUI
import Foundation
import Shell
import Sparkle
import SwiftUI

/// E12-2 (D-7): the app updates itself. Sparkle checks the EdDSA-signed appcast on ainkrad.io every four hours and downloads
/// by itself (`SUAutomaticallyUpdate`); when an update is ready it is installed on quit, and this class turns that into the
/// mockup's "restart when you are idle" toast. Idle means no key or click for ten minutes. After the relaunch the new
/// version shows its What is new sheet once.
@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    /// Seconds without any input before the restart happens by itself.
    static let idleNeeded: TimeInterval = 600
    private var controller: SPUStandardUpdaterController?
    private let shell: ShellModel
    private var installNow: (() -> Void)?
    private var idleTask: Task<Void, Never>?

    init(shell: ShellModel) {
        self.shell = shell
        super.init()
        // A Debug build never checks the live feed: it would offer the Release build to a developer's working copy.
        #if DEBUG
        let start = false
        #else
        let start = true
        #endif
        controller = SPUStandardUpdaterController(
            startingUpdater: start, updaterDelegate: self, userDriverDelegate: nil)
        showInstalledNews()
        // Settings, Updates (Shell's page) shows the version and runs these.
        shell.updates.appVersion = Self.version
        // The tab's Check now looks quietly (no Sparkle window); the menu's Check for Updates… keeps Sparkle's own.
        shell.updates.checkApp = { [weak self] in self?.controller?.updater.checkForUpdatesInBackground() }
        shell.updates.installApp = { [weak self] in self?.restartNow() }
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    func check() { controller?.checkForUpdates(nil) }

    private func showInstalledNews() {
        guard let n = WhatsNewStore.take(installed: Self.version), !n.items.isEmpty else { return }
        shell.presentSheet(
            title: "What is new in \(n.version)", message: WhatsNew.message(n.items),
            actions: [ShellSheetAction("Done", primary: true)], symbol: "sparkles")
    }

    // MARK: SPUUpdaterDelegate

    /// The automatic download started: Settings, Updates shows it downloading in the background.
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        shell.updates.appDownloading = item.displayVersionString
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        shell.updates.appDownloading = nil
    }

    /// An update is downloaded and will install when the app quits. Handled here: keep its notes for after the relaunch, say
    /// so, and restart by ourselves once the Mac is idle.
    func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        installNow = immediateInstallHandler
        shell.updates.appDownloading = nil
        shell.updates.appReady = item.displayVersionString
        WhatsNewStore.save(version: item.displayVersionString, items: WhatsNew.parse(item.itemDescription ?? ""))
        shell.showToast(
            "A new version is ready. Ainkrad \(item.displayVersionString) restarts when you are idle.", kind: .info,
            actionTitle: "Restart now", lifetime: 30
        ) { [weak self] in self?.restartNow() }
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                if Self.idleSeconds() >= Self.idleNeeded {
                    self.restartNow()
                    return
                }
            }
        }
        return true
    }

    private func restartNow() {
        idleTask?.cancel()
        let go = installNow
        installNow = nil
        shell.updates.appReady = nil
        go?()
    }

    private static func idleSeconds() -> TimeInterval {
        // kCGAnyInputEventType: the time since any key, click or pointer move.
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
    }
}
