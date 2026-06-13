import XCTest

@MainActor
final class ShadowConsoleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-SmartShadowPreviewAuthenticated"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testRepoRadarNavigatesToRepoAndIssueDetail() throws {
        XCTAssertTrue(app.staticTexts["WORK"].waitForExistence(timeout: 4))
        XCTAssertTrue(element(identifier: "repoCard-smart-shadow").waitForExistence(timeout: 6))
        XCTAssertTrue(staticText(containing: "Next: Ship repo-first console").exists)
        XCTAssertTrue(app.staticTexts["Review"].exists)
        XCTAssertTrue(app.staticTexts["Agent"].exists)
        XCTAssertTrue(app.staticTexts["executing"].exists)
        XCTAssertTrue(element(identifier: "repoLabels-smart-shadow").exists)
        XCTAssertTrue(element(identifier: "repoLabels-smart-shadow").label.contains("ios"))
        XCTAssertTrue(element(identifier: "repoLabels-smart-shadow").label.contains("macos"))
        XCTAssertTrue(element(identifier: "repoLabels-smart-shadow").label.contains("life-os"))
        XCTAssertTrue(element(identifier: "shadowOrb").exists)

        tapElement(identifier: "repoCard-smart-shadow")

        XCTAssertTrue(app.staticTexts["Issues (11)"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["PRs (2)"].exists)
        XCTAssertTrue(app.staticTexts["Sync"].exists)
        XCTAssertTrue(app.staticTexts["Review"].exists)
        XCTAssertTrue(app.staticTexts["Agent"].exists)
        XCTAssertTrue(element(identifier: "repoDetailLabels-smart-shadow").exists)
        XCTAssertTrue(app.staticTexts["Ship repo-first console and verify simulator flow."].exists)
        XCTAssertTrue(element(identifier: "shadowOrb").exists)

        tapElement(identifier: "issueRow-42")

        XCTAssertTrue(app.staticTexts["#42"].waitForExistence(timeout: 4))
        XCTAssertTrue(staticText(containing: "Implement repo board grouping").exists)
        XCTAssertTrue(app.staticTexts["Summary"].exists)
        XCTAssertTrue(app.staticTexts["Timeline"].exists)
        XCTAssertTrue(app.staticTexts["Comments"].exists)
        XCTAssertTrue(element(identifier: "shadowOrb").exists)
    }

    func testShadowOrbOpensCommandPanelFromRepoBoard() throws {
        let orb = element(identifier: "shadowOrb")
        XCTAssertTrue(orb.waitForExistence(timeout: 4))
        orb.tap()

        XCTAssertTrue(app.navigationBars["Shadow Command"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["shadowCommandText"].exists)
        XCTAssertTrue(app.buttons["shadowVoiceButton"].exists)
        XCTAssertTrue(app.buttons["shadowGenerateButton"].exists)
    }

    func testMinePageShowsControlPlaneSections() throws {
        tapElement(identifier: "shadowTab-我的")

        XCTAssertTrue(app.staticTexts["我的"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["GitHub"].exists)
        XCTAssertTrue(app.staticTexts["Shadow"].exists)
        XCTAssertTrue(app.staticTexts["Life OS"].exists)
        XCTAssertTrue(app.staticTexts["Safety"].exists)
        XCTAssertTrue(staticText(containing: "confirm before write").exists)
        XCTAssertTrue(staticText(containing: "confirmation required").exists)
    }

    func testCommandPanelGeneratesConfirmationGatedIssueFromSelectedRepo() throws {
        tapElement(identifier: "repoCard-smart-shadow")
        XCTAssertTrue(app.staticTexts["Issues (11)"].waitForExistence(timeout: 6))

        let orb = element(identifier: "shadowOrb")
        XCTAssertTrue(orb.exists)
        orb.tap()

        XCTAssertTrue(app.navigationBars["Shadow Command"].waitForExistence(timeout: 4))
        let commandText = element(identifier: "shadowCommandText")
        XCTAssertTrue(commandText.waitForExistence(timeout: 4))
        commandText.tap()
        commandText.typeText("Create an issue to review the visual console polish")

        app.buttons["shadowGenerateButton"].tap()

        XCTAssertTrue(app.staticTexts["Confirmation required"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["shadowConfirmExecuteButton"].exists)
        XCTAssertTrue(staticText(containing: "Create issue in smart-shadow").exists)
    }

    private func tapElement(identifier: String, timeout: TimeInterval = 6) {
        let element = element(identifier: identifier)
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Expected \(identifier) to exist")
        element.tap()
    }

    private func element(identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func staticText(containing text: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
