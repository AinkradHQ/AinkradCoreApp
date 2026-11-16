import XCTest

/// The AI sessions screens against a real local Core and a runner with a stand-in `claude` (no provider, no credentials).
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
        app.activate()  // another app may have come forward meanwhile; the launcher only takes keys in the active app
        app.typeKey("k", modifierFlags: .command)
        if !launcher.waitForExistence(timeout: 4) { app.typeKey("k", modifierFlags: .command) }
        XCTAssertTrue(launcher.waitForExistence(timeout: 5), "⌘K opens the launcher")
        launcher.click()
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
        try LivePairing.pair(app, env: env)

        // The list, live: nothing yet.
        run("ai sessions")
        XCTAssertTrue(containing("AI Sessions, Home Core").waitForExistence(timeout: 10), "the list pane opens")
        // The script starts the first session a while after pairing; the list is empty until then.
        _ = app.staticTexts["No AI sessions yet"].waitForExistence(timeout: 8)
        shot("list-empty")

        // A session started from outside arrives over the event stream and waits on the approval.
        let waiting = containing("on runner-1, Needs you")
        let arrived = waiting.waitForExistence(timeout: 60)
        shot("list-waiting")
        XCTAssertTrue(arrived, "the new session shows in the list, waiting on you")

        // Approved from the inbox (Touch ID is a software key here); the Core tells the agent. Sessions stay open between
        // messages now, so it goes back to waiting for you rather than ending.
        run("approvals")
        XCTAssertTrue(containing("wants to").waitForExistence(timeout: 20), "the inbox has the request")
        shot("inbox")
        XCTAssertTrue(containing("git push").exists)
        app.buttons["Approve Bash"].firstMatch.click()
        XCTAssertTrue(app.buttons["Approve Bash"].waitForNonExistence(timeout: 30), "the answer took it off the inbox")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waiting.waitForNonExistence(timeout: 60), "the stand-in was told yes and no longer needs you")

        // A session started from the app opens at once and empty, like typing `claude` in a terminal: no sheet, no prompt field.
        // The first message goes through the composer (Touch ID is a software key here).
        run("new ai session")
        let composer1 = app.textViews["agent-composer"]
        XCTAssertTrue(composer1.waitForExistence(timeout: 30), "a new session opens its pane with the composer")
        shot("new-session-empty")
        composer1.click()
        composer1.typeText("add the v25 migration")
        shot("new-session-typed")
        composer1.typeKey(.return, modifierFlags: [])
        shot("after-first-message")
        XCTAssertTrue(containing("wants to").waitForExistence(timeout: 30), "its approval shows above the composer")
        shot("session-waiting")
        app.buttons["Deny Bash"].firstMatch.click()
        XCTAssertTrue(containing("Denied").waitForExistence(timeout: 30), "the denial is in the transcript")
        shot("session-denied")

        // The same session again (open sessions keep their runner slot, so a third would find this runner full): a second
        // message, which the composer clears once sent.
        let composer = composer1
        composer.click()
        composer.typeText("please be quick")
        composer.typeKey(.return, modifierFlags: [])
        let cleared = NSPredicate(format: "value == '' OR value == nil OR value BEGINSWITH 'Message '")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: cleared, object: composer)], timeout: 30),
            .completed, "a sent message leaves the composer")
        XCTAssertTrue(containing("wants to").waitForExistence(timeout: 30), "the second turn asks again")
        // ⇧⇥ in the message field switches the mode through the Core (Core #261), as in Claude Code: the chip changes and
        // the transcript says so. A Core that does not report modes shows no chip; the step is skipped then.
        if containing("Mode: Asks first").waitForExistence(timeout: 5) {
            composer.click()
            composer.typeKey(.tab, modifierFlags: .shift)
            XCTAssertTrue(
                containing("Mode: Accepts edits").waitForExistence(timeout: 20),
                "⇧⇥ switches the mode to Accepts edits")
            XCTAssertTrue(
                containing("Switched to Accepts edits").waitForExistence(timeout: 20), "the transcript says so")
            shot("session-mode")
        } else {
            XCTFail("no mode chip: this Core does not report the session's mode")
        }
        // The session's actions (header, or the side panel's first card on a wide pane): Find opens the find bar.
        app.buttons["Find in this conversation"].firstMatch.click()
        let find = app.textFields["Find in this conversation"]
        XCTAssertTrue(find.waitForExistence(timeout: 5), "Find opens the find bar")
        find.typeText("quick")
        XCTAssertTrue(containing("1 of").waitForExistence(timeout: 5), "the find bar counts the match")
        shot("session-find")
        find.typeKey(.escape, modifierFlags: [])
        // End session asks first, then ends it.
        app.buttons["End Session…"].firstMatch.click()
        XCTAssertTrue(containing("End this AI session?").waitForExistence(timeout: 10), "End session asks first")
        let ends = app.buttons.matching(NSPredicate(format: "label == 'End Session'"))
        ends.element(boundBy: ends.count - 1).click()  // the sheet's button, drawn last
        // An ended session closes its composer (the sidebar's "Ended" would match any label check).
        XCTAssertTrue(composer.waitForNonExistence(timeout: 90), "the session ends and its composer closes")
        shot("session-ended")
    }
}
