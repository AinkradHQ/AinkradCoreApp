import XCTest

/// The Core app against a real local Core. Only with `CORE_IT=1`: `scripts/app-it.sh accounts` starts a throwaway Core and
/// approves the app's pairing. Lists accounts (none: a throwaway Core holds no provider key, and this app never takes one) and
/// pools, makes a pool, binds an agent to it, unbinds, deletes the pool. The software step-up key elevates, so no Touch ID
/// prompt appears. Events go only to the app under test.
@MainActor
final class AccountsLiveUITests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private var app: XCUIApplication!

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", id, id))
            .firstMatch
    }

    private func openFromLauncher(_ query: String, expect id: String) {
        app.typeKey("k", modifierFlags: .command)
        let launcher = app.textFields["Launcher"]
        if !launcher.waitForExistence(timeout: 4) { app.typeKey("k", modifierFlags: .command) }
        XCTAssertTrue(launcher.waitForExistence(timeout: 10), "⌘K opens the launcher")
        launcher.typeText(query)
        launcher.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element(id).waitForExistence(timeout: 20), "\(query) opens \(id)")
    }

    private func shot(_ name: String) {
        guard let dir = env["CORE_IT_SHOTS"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/accounts-live-\(name).png"))
    }

    private func wait(_ predicate: @escaping () -> Bool, timeout: TimeInterval = 30, _ message: String) {
        let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: timeout), .completed, message)
    }

    func testPoolsAndBindings() throws {
        try XCTSkipUnless(env["CORE_IT"] == "1", "needs a local Core: run scripts/app-it.sh accounts")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["CORE_KEYSTORE"] = "memory"
        app.launchEnvironment["CORE_IT_SAS_FILE"] = try XCTUnwrap(env["CORE_IT_SAS_FILE"])
        app.launch()
        defer { app.terminate() }
        try LivePairing.pair(app, env: env)

        // Overview: no accounts, and the gate says what the Core will accept.
        openFromLauncher("accounts", expect: "accounts-pane")
        let first = app.staticTexts["No accounts yet"]
        _ = first.waitForExistence(timeout: 20)
        shot("overview")
        XCTAssertTrue(
            first.exists, "an empty Core offers the first account. Tree: \(String(app.debugDescription.prefix(6000)))")
        XCTAssertTrue(element("gate-banner").exists, "the gate's state is shown")

        // Pools: the Core's own lists (whatever default pools it has), then a new one.
        element("nav-pools").click()
        XCTAssertTrue(element("pools").waitForExistence(timeout: 20), "the pools page opens")
        let name = app.textFields["Name"]
        for _ in 0..<3 where !name.exists {  // the first click can land while the page is still loading
            app.buttons["New pool"].firstMatch.click()
            _ = name.waitForExistence(timeout: 6)
        }
        XCTAssertTrue(name.exists, "the New pool dialog opens")
        name.click()
        name.typeText("e5-08-test")
        app.buttons["Create pool"].click()
        let tab = element("pool-tab-e5-08-test")
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "the new pool is listed after Touch ID (software key)")
        shot("pool-created")

        // A second pool right after the first (it used to be reported as impossible).
        let again = app.textFields["Name"]
        for _ in 0..<3 where !again.exists {
            app.buttons["New pool"].firstMatch.click()
            _ = again.waitForExistence(timeout: 6)
        }
        XCTAssertTrue(again.exists, "the New pool dialog opens a second time")
        again.click()
        again.typeText("e5-08-second")
        app.buttons["Create pool"].click()
        XCTAssertTrue(
            element("pool-tab-e5-08-second").waitForExistence(timeout: 30), "the second pool is listed too")
        shot("two-pools")

        // Bindings: bind an agent to it, see it, unbind it.
        element("nav-bindings").click()
        XCTAssertTrue(element("bindings").waitForExistence(timeout: 20))
        let agent = app.textFields["Agent"]
        for _ in 0..<3 where !agent.exists {
            app.buttons["Bind an agent"].firstMatch.click()
            _ = agent.waitForExistence(timeout: 6)
        }
        XCTAssertTrue(agent.exists, "the Bind dialog opens")
        agent.click()
        agent.typeText("e5-08-agent")
        app.buttons["e5-08-test"].firstMatch.click()
        app.buttons["Bind agent"].click()
        let row = element("binding-e5-08-agent")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the binding is listed")
        shot("bound")
        app.buttons["Unbind"].firstMatch.click()
        wait({ !self.element("binding-e5-08-agent").exists }, "the binding is gone")

        // Delete the pool again.
        element("nav-pools").click()
        element("pool-tab-e5-08-test").click()
        XCTAssertTrue(app.buttons["Delete pool…"].firstMatch.isEnabled, "a pool that is not the default can be deleted")
        app.buttons["Delete pool…"].firstMatch.click()
        app.buttons["Delete pool"].click()
        wait({ !self.element("pool-tab-e5-08-test").exists }, "the pool is deleted")
        element("pool-tab-e5-08-second").click()
        app.buttons["Delete pool…"].firstMatch.click()
        app.buttons["Delete pool"].click()
        wait({ !self.element("pool-tab-e5-08-second").exists }, "the second pool is deleted")
    }
}
