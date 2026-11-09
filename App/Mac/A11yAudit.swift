#if DEBUG
import AppKit
import ApplicationServices
import Pairing
import Shell

/// Debug only. `CORE_A11Y_AUDIT=<dir>` (with `CORE_DEMO=1`) walks the main screens by changing the app's own state, asks the
/// window for its accessibility tree the way VoiceOver does, and writes every control that has no name to
/// `<dir>/a11y-audit.txt` (screen, role, path). It only logs: nothing here fails the run, so the count is the thing to watch.
@MainActor
enum A11yAudit {
    private static let named: Set<NSAccessibility.Role> = [
        .button, .radioButton, .checkBox, .popUpButton, .menuButton, .link, .slider, .disclosureTriangle, .image,
    ]

    static func run(_ app: AppModel, dir: String, env: [String: String]) async {
        NSApp.appearance = NSAppearance(named: env["CORE_THEME"] == "light" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = NSApp.windows.first(where: { $0.title == "Ainkrad" }) else { return log("no main window") }
        let shell = app.shell
        var report = ["screen | controls | unnamed"]
        var details: [String] = []
        func audit(_ screen: String) async {
            try? await Task.sleep(for: .seconds(1.6))
            var total = 0
            var bad: [String] = []
            walk(window.contentView, path: "", total: &total, bad: &bad)
            if total == 0 { walkAX(&total, &bad) }  // SwiftUI builds its tree for assistive apps; ask the way they do
            report.append("\(screen) | \(total) | \(bad.count)")
            details += bad.map { "\(screen) | \($0)" }
            log("audit \(screen) controls=\(total) unnamed=\(bad.count)")
        }
        app.debugShowDesktop()
        await audit("home")
        shell.toggleLauncher()
        await audit("launcher")
        shell.toggleLauncher()
        shell.toggleBell()
        await audit("bell")
        shell.bellOpen = false
        for id in ["agents", "terminals", "runners"] {
            shell.openPane(SampleWorld.samplePane(id, shell))
            await audit(id)
        }
        shell.closeAllPanes()
        shell.show(.home)
        shell.open(.settings)
        for page in ["appearance", "notifications"] {
            shell.settings.selected = page
            await audit("settings-\(page)")
        }
        shell.closeTopmost()
        let accounts = app.debugAccountsDemo()
        for scene in ["overview", "accounts", "account-ready", "budget-new"] {
            await accounts.show(scene)
            await audit("accounts-\(scene)")
        }
        let brain = app.debugBrainDemo()
        for scene in ["overview", "rooms", "checks"] {
            await brain.show(scene)
            await audit("brain-\(scene)")
        }
        let text = (report + [""] + details).joined(separator: "\n") + "\n"
        try? text.write(toFile: "\(dir)/a11y-audit.txt", atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    /// The same walk through the system accessibility API on this process (what VoiceOver sees). Needs the app to be
    /// trusted for accessibility; says so in the log when it is not.
    private static func walkAX(_ total: inout Int, _ bad: inout [String]) {
        let app = AXUIElementCreateApplication(getpid())
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if !AXIsProcessTrusted() { log("accessibility API not trusted for this process") }
        func text(_ e: AXUIElement, _ key: String) -> String {
            var v: CFTypeRef?
            AXUIElementCopyAttributeValue(e, key as CFString, &v)
            return (v as? String) ?? ""
        }
        func kids(_ e: AXUIElement) -> [AXUIElement] {
            var v: CFTypeRef?
            AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v)
            return (v as? [AXUIElement]) ?? []
        }
        let controls: Set<String> = [
            "AXButton", "AXRadioButton", "AXCheckBox", "AXPopUpButton", "AXMenuButton", "AXLink", "AXSlider",
        ]
        func named(_ e: AXUIElement, _ depth: Int) -> Bool {
            if ![text(e, "AXTitle"), text(e, "AXDescription"), text(e, "AXValue")].allSatisfy(\.isEmpty) {
                return true
            }
            return depth < 4 && kids(e).contains { named($0, depth + 1) }
        }
        func go(_ e: AXUIElement, _ path: String) {
            let role = text(e, "AXRole")
            if role == "AXScrollBar" { return }  // AppKit's own scroll arrows are not this app's controls
            let here = path + "/" + role.replacingOccurrences(of: "AX", with: "")
            if controls.contains(role) {
                total += 1
                if !named(e, 0) { bad.append("\(role) \(here) help=\(text(e, "AXHelp"))") }
            }
            for k in kids(e) { go(k, here) }
        }
        go(app, "")
    }

    /// Depth-first over the accessibility tree. A control is unnamed when neither it nor anything inside it has a title,
    /// label, description or text value.
    private static func walk(_ node: Any?, path: String, total: inout Int, bad: inout [String]) {
        guard let e = node as? NSAccessibilityProtocol else { return }
        let role = e.accessibilityRole()
        let here = path + "/" + (role?.rawValue.replacingOccurrences(of: "AX", with: "") ?? "?")
        if let role, named.contains(role) {
            total += 1
            if !hasName(e, depth: 0) { bad.append("\(role.rawValue) \(here) help=\(e.accessibilityHelp() ?? "-")") }
        }
        for child in e.accessibilityChildren() ?? [] { walk(child, path: here, total: &total, bad: &bad) }
    }

    private static func hasName(_ e: NSAccessibilityProtocol, depth: Int) -> Bool {
        let own = [e.accessibilityLabel(), e.accessibilityTitle(), e.accessibilityValue() as? String]
        if own.contains(where: { !($0 ?? "").isEmpty }) { return true }
        guard depth < 4 else { return false }
        return (e.accessibilityChildren() ?? []).contains {
            ($0 as? NSAccessibilityProtocol).map { hasName($0, depth: depth + 1) } ?? false
        }
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("SNAP \(s)\n".utf8)) }
}
#endif
