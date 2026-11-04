import XCTest

/// The agents screens against a real local Core and a runner with a stand-in `claude` (no provider, no credentials).
/// Only with `CORE_IT=1`: `scripts/app-it.sh agents` starts the Core and the runner, plays the approver for the app's pairing,
/// and starts the first session from outside a little after the app is paired (this runner cannot write signal files).
/// The stand-in prints an assistant message, one tool call and its result, asks for one approval (a push), and ends the turn.
/// Events go only to the app under test.
@MainActor
final class AgentsLiveUITests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private var app: XCUIApplication!

    private func containing(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        ).firstMatch
    }
    private var shots = 0
    /// The app's own window pixels as a kept attachment: the script exports them from the result bundle (this runner cannot write
    /// outside its container), for the review set and for diagnosing a failure.
    private func shot(_ name: String) {
        shots += 1
        guard app.windows.firstMatch.exists else {
            let t = XCTAttachment(string: app.debugDescription)
            t.name = "live-\(shots)-\(name)-no-window"
            t.lifetime = .keepAlways
            add(t)
            return
        }
        let a = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        a.name = "live-\(String(format: "%02d", shots))-\(name)"
        a.lifetime = .keepAlways
        add(a)
    }
    private var launcher: XCUIElement { app.textFields["Launcher"] }

    private func run(_ query: String) {
        app.typeKey("k", modifierFlags: .command)
        if !launcher.waitForExistence(timeout: 4) { app.typeKey("k", modifierFlags: .command) }
        XCTAssertTrue(launcher.waitForExistence(timeout: 5), "⌘K opens the launcher")
        launcher.typeText(query)
        launcher.typeKey(.return, modifierFlags: [])
    }

    func testListApprovalsAndSessionsAgainstALocalCore() throws {
        try XCTSkipUnless(env["CORE_IT"] == "1", "needs a local Core: run scripts/app-it.sh agents")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["CORE_KEYSTORE"] = "memory"  // no Keychain; a software step-up key, so no Touch ID prompt
        app.launchEnvironment["CORE_IT_SAS_FILE"] = try XCTUnwrap(env["CORE_IT_SAS_FILE"])
        app.launch()
        defer { app.terminate() }
        try LivePairing.pair(
            app, url: try XCTUnwrap(env["CORE_IT_URL"]), code: try XCTUnwrap(env["CORE_IT_CODE"]),
            sasFile: env["CORE_IT_SAS_FILE"])

        // The list, live: nothing yet.
        run("agents")
        XCTAssertTrue(containing("Agents, Home Core").waitForExistence(timeout: 10), "the list pane opens")
        // The script starts the first session a while after pairing; the list is empty until then.
        _ = app.staticTexts["No agent sessions yet"].waitForExistence(timeout: 8)
        shot("list-empty")

        // A session started from outside arrives over the event stream and waits on the approval.
        let waiting = containing("on runner-1, Waiting on you")
        let arrived = waiting.waitForExistence(timeout: 60)
        shot("list-waiting")
        XCTAssertTrue(arrived, "the new session shows in the list, waiting on you")

        // ⌘Return approves it from the inbox: Touch ID (a software key here), then the Core tells the agent.
        run("approvals")
        XCTAssertTrue(containing("wants to use Bash").waitForExistence(timeout: 20), "the inbox has the request")
        shot("inbox")
        XCTAssertTrue(containing("git push").exists)
        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(containing("Decided").waitForExistence(timeout: 30), "the answer moved it to Decided")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            containing("on runner-1, Succeeded").waitForExistence(timeout: 60), "the stand-in was told yes and finished"
        )

        // A session started from the app: the sheet, the runner picked for you, ⌘Return starts it (step-up already done).
        run("new agent")
        let prompt = app.textViews["Prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 15), "the sheet has its prompt")
        shot("new-session")
        XCTAssertTrue(app.buttons["Start session"].exists)
        app.typeText("add the v25 migration")  // the sheet focuses its prompt
        shot("new-session-typed")
        app.typeKey(.return, modifierFlags: .command)
        shot("after-start")
        XCTAssertTrue(
            app.textFields["agent-composer"].waitForExistence(timeout: 30), "starting opens the session pane")
        XCTAssertTrue(containing("wants to use Bash").waitForExistence(timeout: 30), "its approval shows in the pane")
        shot("session-waiting")
        app.typeKey(.delete, modifierFlags: .command)  // ⌘⌫ denies
        XCTAssertTrue(containing("Denied").waitForExistence(timeout: 30), "the denial is in the transcript")
        XCTAssertTrue(containing("Ended: succeeded").waitForExistence(timeout: 60), "the stand-in stopped when told no")
        shot("session-denied-ended")

        // Another: the composer, then Cancel with its confirmation.
        run("new agent")
        let prompt2 = app.textViews["Prompt"]
        XCTAssertTrue(prompt2.waitForExistence(timeout: 15))
        app.typeText("second one")
        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(containing("wants to use Bash").waitForExistence(timeout: 30))
        let fields = app.textFields.matching(identifier: "agent-composer")
        let composer = fields.element(boundBy: max(fields.count - 1, 0))  // the newest pane is the last
        composer.click()
        composer.typeText("please be quick")
        composer.typeKey(.return, modifierFlags: [])
        let cleared = NSPredicate(format: "value == '' OR value == nil OR value == 'Reply to claude…'")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: cleared, object: composer)], timeout: 30),
            .completed, "a sent message leaves the composer")
        app.buttons["Cancel"].click()
        XCTAssertTrue(containing("Cancel this session?").waitForExistence(timeout: 10), "Cancel asks first")
        app.buttons["Cancel session"].click()
        XCTAssertTrue(containing("Cancelled").waitForExistence(timeout: 90), "the session ends as cancelled")
        shot("session-cancelled")
    }
}
