import XCTest

/// Keyboard and pointer paths of the shell chrome that follow the prototype: launcher keys, closing and reopening a pane, focus
/// mode tabs, the elevation panel and the Activity setting. The sample world (`CORE_DEMO=1`), no Core.
@MainActor
final class ShellParityUITests: XCTestCase {
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

    private var launcher: XCUIElement { app.textFields["Launcher"] }

    private func openLauncher() {
        app.typeKey("k", modifierFlags: .command)
        if !launcher.waitForExistence(timeout: 4) { app.typeKey("k", modifierFlags: .command) }
        XCTAssertTrue(launcher.waitForExistence(timeout: 5), "⌘K opens the launcher")
    }

    private func openAgents() {
        openLauncher()
        launcher.typeText("agents")
        launcher.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["Show Home"].waitForExistence(timeout: 5), "a pane opens the workspace")
    }

    func testControlNMovesTheSelectionDown() {
        openLauncher()
        launcher.typeKey("n", modifierFlags: .control)  // recents: Core, Agents, Terminals
        launcher.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            app.descendants(matching: .any)["Agents, Home Core"].waitForExistence(timeout: 5),
            "⌃N then Return runs the second row")
    }

    func testClosingAPaneOffersUndoAndShiftCommandTReopens() {
        openAgents()
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(
            app.staticTexts["Closed Agents. It keeps running."].waitForExistence(timeout: 5),
            "closing a pane says it keeps running")
        XCTAssertTrue(app.buttons["Undo"].exists, "with an Undo")
        app.typeKey("t", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.descendants(matching: .any)["Agents, Home Core"].waitForExistence(timeout: 5), "⇧⌘T reopens")
    }

    func testFocusModeShowsTabsInTheTitleStrip() {
        openAgents()
        app.typeKey("f", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["Focus Agents"].waitForExistence(timeout: 5), "focus mode lists the panes as tabs")
        app.typeKey("f", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["Focus Agents"].waitForNonExistence(timeout: 5), "and tiles them again")
    }

    func testTheElevationChipOpensItsPanelAndEscapeCloses() {
        let chip = app.buttons["Touch ID elevation: admin actions are locked"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.click()
        XCTAssertTrue(app.buttons["Unlock with Touch ID"].waitForExistence(timeout: 5), "the panel offers Touch ID")
        XCTAssertTrue(app.staticTexts["Admin actions are locked"].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["Unlock with Touch ID"].waitForNonExistence(timeout: 5), "Esc closes it")
    }

    func testActivityChipFollowsItsSetting() {
        let chip = app.buttons.matching(NSPredicate(format: "label CONTAINS 'running,'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the sample world has something running")
        app.typeKey(",", modifierFlags: .command)
        let activity = app.buttons["Activity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        activity.click()
        let toggle = app.descendants(matching: .any)["switch-Status bar chip"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Settings, Activity has the chip switch")
        toggle.click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(chip.waitForNonExistence(timeout: 5), "off: the chip leaves the status cluster")
    }
}
