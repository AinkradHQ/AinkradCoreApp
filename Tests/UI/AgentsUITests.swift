import XCTest

/// Keyboard paths of the agents area, on the sample world (`CORE_DEMO=1`: no Core). XCUITest sends events only to the app under test.
@MainActor
final class AgentsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["CORE_DEMO"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Show workspace"].waitForExistence(timeout: 10))
    }

    override func tearDown() async throws { app.terminate() }

    private func element(_ label: String) -> XCUIElement { app.descendants(matching: .any)[label].firstMatch }
    private func containing(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        ).firstMatch
    }
    private var launcher: XCUIElement { app.textFields["Launcher"] }

    private func run(_ query: String) {
        app.typeKey("k", modifierFlags: .command)
        if !launcher.waitForExistence(timeout: 4) { app.typeKey("k", modifierFlags: .command) }
        XCTAssertTrue(launcher.waitForExistence(timeout: 5), "⌘K opens the launcher")
        launcher.typeText(query)
        launcher.typeKey(.return, modifierFlags: [])
    }

    func testApprovalsFromTheLauncherAnswerWithTheKeyboard() {
        run("approvals")
        XCTAssertTrue(containing("wants to use").waitForExistence(timeout: 10), "the inbox lists what agents wait for")
        app.typeKey(.return, modifierFlags: .command)  // ⌘Return approves the first card
        // This sample has no Core to ask for Touch ID: the refusal shows in the card, and the request stays.
        XCTAssertTrue(containing("Touch ID did not run").waitForExistence(timeout: 10), "⌘Return reached the approval")
        XCTAssertTrue(containing("wants to use").exists, "a refused answer leaves the request waiting")
        app.typeKey(.delete, modifierFlags: .command)  // ⌘⌫ denies
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Approvals"].waitForNonExistence(timeout: 5), "Esc closes the inbox")
    }

    func testTheListOpensASessionWithItsComposer() {
        run("agents")
        XCTAssertTrue(element("Agents, Home Core").waitForExistence(timeout: 10), "the list pane opens")
        XCTAssertTrue(app.buttons["New"].waitForExistence(timeout: 10))
        let row = containing("on mac-studio").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "sessions are listed")
        row.click()
        XCTAssertTrue(
            app.textFields["agent-composer"].waitForExistence(timeout: 10), "a session pane has its composer")
        let composer = app.textFields["agent-composer"]
        Thread.sleep(forTimeInterval: 1)  // the pane is still settling into place
        composer.click()
        composer.typeText("hi")
        XCTAssertEqual(composer.value as? String, "hi", "typing reaches the composer and its value can be read")
        // Return sends; this sample has no Core, so the refusal shows in place.
        composer.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            containing("Touch ID did not run").waitForExistence(timeout: 10), "a send that cannot go through says so")
    }

    func testSeveralPanesStayReadableToAccessibility() {
        run("agents")
        XCTAssertTrue(element("Agents, Home Core").waitForExistence(timeout: 10))
        run("claude")
        XCTAssertTrue(app.textFields["agent-composer"].waitForExistence(timeout: 10), "a session opens beside the list")
        run("codex")
        Thread.sleep(forTimeInterval: 1)
        // Reading the whole tree with several session panes open once overflowed the stack (see `agentCopyMenu`).
        XCTAssertGreaterThanOrEqual(
            app.textFields.matching(identifier: "agent-composer").count, 2, "two sessions beside the list can be read")
    }

    func testNewSessionSheetOpensFromTheLauncherAndEscapeClosesIt() {
        run("new agent")
        XCTAssertTrue(app.staticTexts["New agent session"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Start session"].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["Start session"].waitForNonExistence(timeout: 5), "Esc closes the sheet")
    }
}
