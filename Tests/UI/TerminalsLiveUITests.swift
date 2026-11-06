import XCTest

/// A terminal end to end, against a real local Core with a runner that offers `pty`. Only with `CORE_IT=1`:
/// `scripts/app-it.sh terminals` starts the Core and the runner and approves the app's pairing. The app keeps its keys in
/// memory and elevates with a software step-up key, so no Touch ID prompt appears. Events go only to the app under test.
@MainActor
final class TerminalsLiveUITests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private var app: XCUIApplication!

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", label, label))
            .firstMatch
    }
    private var screen: XCUIElement { element("Terminal screen") }
    private func screenText() -> String { (screen.value as? String) ?? "" }

    private func waitForScreen(containing text: String, timeout: TimeInterval = 30, _ message: String) {
        let has = NSPredicate { _, _ in self.screenText().contains(text) }
        let done = XCTNSPredicateExpectation(predicate: has, object: nil)
        let ok = XCTWaiter().wait(for: [done], timeout: timeout) == .completed
        if !ok, let dir = env["CORE_IT_SHOTS"] {  // what the window showed when it did not
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/terminal-live-failure.png"))
        }
        XCTAssertTrue(ok, "\(message). Screen: \(screenText().suffix(300).replacingOccurrences(of: "\n", with: " ⏎ "))")
    }

    func testOpenTypeDetachReattachAndEndATerminal() throws {
        try XCTSkipUnless(env["CORE_IT"] == "1", "needs a local Core with a runner: run scripts/app-it.sh terminals")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["CORE_KEYSTORE"] = "memory"
        app.launchEnvironment["CORE_IT_SAS_FILE"] = try XCTUnwrap(env["CORE_IT_SAS_FILE"])
        app.launch()
        defer { app.terminate() }
        try LivePairing.pair(app, env: env)

        // ⌘K, "new terminal advanced", Return: the advanced sheet lists the runner; Open terminal. (Plain New terminal
        // opens one at once with the defaults.)
        app.typeKey("k", modifierFlags: .command)
        let launcher = app.textFields["Launcher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 10))
        launcher.typeText("new terminal advanced")
        launcher.typeKey(.return, modifierFlags: [])
        let open = app.buttons["Open terminal"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the New terminal sheet opens")
        let runner = app.buttons.matching(NSPredicate(format: "label MATCHES '.*, (Online|Degraded).*'")).firstMatch
        XCTAssertTrue(runner.waitForExistence(timeout: 20), "the runner is listed and connected")
        XCTAssertTrue(open.isEnabled, "a runner with a pty driver is chosen")
        open.click()

        // The pane attaches (software step-up), the shell is live: type, see the answer.
        XCTAssertTrue(screen.waitForExistence(timeout: 30), "the terminal pane shows its screen")
        let started = NSPredicate { _, _ in self.screenText().count > 20 }
        let shell = XCTNSPredicateExpectation(predicate: started, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [shell], timeout: 30), .completed, "the shell drew its prompt")
        screen.click()  // focus the screen the way a person would
        screen.typeText("echo live-$((40+2))-ok\n")
        waitForScreen(containing: "live-42-ok", "the echo came back")

        // Detach from the pane's tab menu: the terminal keeps running and says so.
        // ⇧⌘A lists the pane's actions; type and Return.
        app.typeKey("a", modifierFlags: [.command, .shift])
        app.textFields["Launcher"].typeText("detach\n")
        XCTAssertTrue(element("Still running").waitForExistence(timeout: 10), "detached: still running, not attached")
        XCTAssertTrue(app.buttons["Attach here"].exists || app.buttons["Attach"].exists)

        // Attach again: the screen comes back with what was on it, and typing works.
        (app.buttons["Attach here"].exists ? app.buttons["Attach here"] : app.buttons["Attach"]).click()
        XCTAssertTrue(screen.waitForExistence(timeout: 30))
        waitForScreen(containing: "live-42-ok", "the earlier output is back after reattach")
        screen.click()
        screen.typeText("echo again-$((50+5))-ok\n")
        waitForScreen(containing: "again-55-ok", "typing works after reattach")

        // End it from the tab menu: confirm, then the pane says it ended.
        app.typeKey("a", modifierFlags: [.command, .shift])
        app.textFields["Launcher"].typeText("end terminal\n")
        let confirm = app.buttons["End terminal"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "the confirm sheet asks")
        confirm.click()
        // The Core drops an ended terminal's output at once when a client closes it ("reaped"): the pane says so.
        let exited = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Exited' OR label == 'Output is gone'")).firstMatch
        XCTAssertTrue(exited.waitForExistence(timeout: 30), "the pane shows the terminal exited")
        XCTAssertTrue(app.buttons["Close pane"].exists)
    }
}
