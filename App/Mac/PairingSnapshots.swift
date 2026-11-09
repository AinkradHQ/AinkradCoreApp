#if DEBUG
import AppKit
import Pairing
import SwiftUI

/// Debug only. `CORE_PAIR_SNAPSHOT=<dir>` walks every first-run state and Touch ID state by setting the app's own state, then, when
/// `CORE_IT_URL` and `CORE_IT_CODE` name a local throwaway Core, pairs with it for real and shoots Devices, Add device
/// and Lockouts with live data. A script (`scripts/app-it.sh shots`) plays the approver and the second device. No key events.
@MainActor
enum PairingSnapshots {
    static func run(_ app: AppModel, dir: String, env: [String: String]) async {
        logPath = "\(dir)/snap.log"
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = NSApp.windows.first(where: { $0.title == "Ainkrad" }) else {
            return log("no main window")
        }
        var n = 0
        func shot(_ name: String, wait: Double = 1.4) async {
            try? await Task.sleep(for: .seconds(wait))
            n += 1
            let file = "\(dir)/\(String(format: "%02d", n))-\(name)-\(theme)-app.png"
            let ok = capture(window, to: file)
            let status = ok ? 0 : 1
            log("shot \(n) \(name) status=\(status)")
            return
        }
        func until(_ what: String, _ seconds: Int = 90, _ ok: @MainActor () -> Bool) async -> Bool {
            for _ in 0..<(seconds * 10) where !ok() { try? await Task.sleep(for: .milliseconds(100)) }
            let good = ok()
            if !good { log("TIMEOUT waiting for \(what)") }
            return good
        }

        for scene in AppModel.wizardScenes {
            app.debugWizard(scene)
            await shot("wizard-\(scene)")
        }
        for scene in AppModel.firstRunScenes {
            app.debugFirstRun(scene)
            await shot("firstrun-\(scene)")
        }
        guard let url = env["CORE_IT_URL"], let code = env["CORE_IT_CODE"] else { return NSApp.terminate(nil) }

        // Live: pair with the throwaway Core. The script approves once it reads the check code from CORE_IT_SAS_FILE.
        app.debugFirstRun("empty")
        await app.debugPair(endpoint: url, code: code)
        await shot("live-sas")
        if await until("the approver", 60, { app.debugFirstRunStage == "approver-approved" }) {
            await shot("live-sas-approved")
        }
        await app.debugConfirmMatch()
        if await until("approved", 30, { app.debugFirstRunStage == "approved" }) {
            await shot("live-approved")
            app.debugFinishFirstRun()
        }
        _ = await until("live desktop", 30) { app.debugLinkIsLive && app.debugDevices > 0 }
        await shot("desktop-live")

        app.debugOpenSettings("devices")
        await shot("devices")
        app.shell.overlay = nil
        app.debugOpenAddDevice()
        await shot("add-device-form")
        await app.debugCreateAddDevice(name: "iPhone")
        if let c = app.debugPairingCode, let out = env["CORE_IT_ADD_CODE_FILE"] {
            try? c.write(toFile: out, atomically: true, encoding: .utf8)
        }
        await shot("add-device-code")
        if await until("the second device to claim", 60, { app.debugAddStage == "claimed" }) {
            await shot("add-device-claimed")
            app.debugTypeAddDeviceCheck(half: true)
            await shot("add-device-typing", wait: 0.6)
            await app.debugApproveAddDevice()
            await shot("add-device-approved")
        }
        app.debugCloseDialog()
        await app.debugReload()
        app.debugOpenSettings("devices")
        await shot("devices-after")
        if let ready = env["CORE_IT_LOCKS_READY"] {
            _ = await until("the lockouts", 120) { FileManager.default.fileExists(atPath: ready) }
        }
        await app.debugReload()
        app.debugOpenSettings("lockouts")
        app.debugSampleLockouts()  // the throwaway Core rarely locks anything: two sample locks show the countdown rows
        await shot("lockouts")
        app.shell.overlay = nil
        await shot("elevated-chip")
        app.shell.elevationPanelOpen = true
        await shot("elevated-panel", wait: 0.6)
        app.shell.elevationPanelOpen = false
        app.shell.coreLink = .reconnecting
        await shot("banner-reconnecting")
        app.shell.coreLink = .offline
        await shot("banner-offline")
        app.shell.coreLink = .live
        app.debugStepUp()
        await shot("stepup-asking")
        app.debugCloseStepUp()
        // Touch ID outcomes are inline, in the panel that asked: here the Rename dialog of a real device.
        app.debugOpenSettings("devices")
        app.debugDetail(named: "iPhone")
        await shot("device-detail")
        app.debugOpenRename(named: "iPhone")
        await shot("device-rename")
        app.debugOpenDialog("scopes", named: "iPhone")
        await shot("device-scopes")
        app.debugCloseDialog()
        app.debugOpenDialog("revoke", named: "iPhone")
        await shot("device-revoke")
        app.debugCloseDialog()
        app.debugOpenRename(named: "iPhone")
        for scene in ["cancelled", "failed", "nokey"] {
            app.debugNotice(scene, done: "renamed")
            await shot("stepup-\(scene)")
        }
        app.debugClearNotice()
        app.debugCloseDialog()
        app.debugDetail(named: nil)
        // Revoke the bootstrap admin: this Mac is then the only device that can manage the Core, and the list says so.
        app.debugOpenSettings("devices")
        await app.debugRevoke(named: "admin")
        await shot("devices-only-admin")
        NSApp.terminate(nil)
    }

    /// The window's own pixels, through the window server: an app may always read its own windows, no screen permission needed.
    private static func capture(_ window: NSWindow, to path: String) -> Bool {
        guard
            let image = CGWindowListCreateImage(
                .null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                [.boundsIgnoreFraming, .nominalResolution])
        else { return false }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    nonisolated(unsafe) static var logPath: String?
    private static func log(_ s: String) {
        FileHandle.standardError.write(Data("SNAP \(s)\n".utf8))
        guard let path = logPath else { return }
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(Data("\(s)\n".utf8))
            try? h.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: Data("\(s)\n".utf8))
        }
    }
}
#endif
