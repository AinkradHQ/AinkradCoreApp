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
        shell.settings.section(
            SettingsSection(
                id: "updates", group: .mac, title: "Updates", sub: "Ainkrad updates itself",
                symbol: "arrow.down.circle",
                order: 6
            ) { UpdatesSection(version: Self.version) { [weak self] in self?.check() } })
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

    /// An update is downloaded and will install when the app quits. Handled here: keep its notes for after the relaunch, say
    /// so, and restart by ourselves once the Mac is idle.
    func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        installNow = immediateInstallHandler
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
        go?()
    }

    private static func idleSeconds() -> TimeInterval {
        // kCGAnyInputEventType: the time since any key, click or pointer move.
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
    }
}

/// Settings, Mac, Updates: the version and a button for the person who wants to look now.
private struct UpdatesSection: View {
    let version: String
    let check: () -> Void

    var body: some View {
        GlassSection(
            "Updates", sub: "Ainkrad, the Core and the runners update by themselves, at night.",
            symbol: "arrow.down.circle", hue: GlassInk.blue
        ) {
            HStack(spacing: Space.s3) {
                Text("Version \(version)").coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                Spacer(minLength: Space.s3)
                Button("Check for updates", action: check).buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        }
        .foregroundStyle(GlassInk.primary)
    }
}
