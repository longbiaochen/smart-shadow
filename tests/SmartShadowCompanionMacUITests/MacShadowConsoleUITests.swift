import XCTest

@MainActor
final class MacShadowConsoleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-SmartShadowPreviewAuthenticated", "-SmartShadowForcePreviewData"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testThreeColumnRepoRadarNavigatesToIssueDetail() throws {
        XCTAssertTrue(app.staticTexts["WORK"].waitForExistence(timeout: 8))
        XCTAssertTrue(staticText(containing: "Repo radar").exists)
        XCTAssertTrue(staticText(containing: "Next: Verify macOS three-column").exists)
        XCTAssertTrue(app.staticTexts["Review"].exists)
        XCTAssertTrue(app.staticTexts["Agent"].exists)
        XCTAssertTrue(app.staticTexts["executing"].exists)
        XCTAssertTrue(element(identifier: "macRepoLabels-smart-shadow").exists)
        XCTAssertTrue(element(identifier: "macRepoLabels-smart-shadow").label.contains("system"))
        XCTAssertTrue(element(identifier: "macRepoLabels-smart-shadow").label.contains("github"))
        XCTAssertTrue(element(identifier: "macRepoLabels-smart-shadow").label.contains("shadow"))
        XCTAssertTrue(element(identifier: "shadowOrb").exists)

        tapElement(identifier: "macRepoCard-smart-shadow")

        XCTAssertTrue(staticText(containing: "Verify macOS three-column shadow console.").waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Issues"].exists)
        XCTAssertTrue(app.staticTexts["PRs"].exists)
        XCTAssertTrue(app.staticTexts["Sync"].exists)
        XCTAssertTrue(app.staticTexts["Review"].exists)
        XCTAssertTrue(app.staticTexts["Agent"].exists)
        XCTAssertTrue(element(identifier: "macRepoDetailLabels-smart-shadow").exists)

        tapElement(identifier: "macIssueRow-12")

        XCTAssertTrue(staticText(containing: "#12").waitForExistence(timeout: 4))
        XCTAssertTrue(staticText(containing: "设计 repo board 的 iOS 交互").exists)
        XCTAssertTrue(app.staticTexts["Summary"].exists)
        XCTAssertTrue(app.staticTexts["Timeline"].exists)
        XCTAssertTrue(app.staticTexts["Comments"].exists)
    }

    func testShadowOrbAndCommandKOpenCommandPanel() throws {
        let orb = element(identifier: "shadowOrb")
        XCTAssertTrue(orb.waitForExistence(timeout: 8))
        orb.tap()

        XCTAssertTrue(element(identifier: "macCommandPanel").waitForExistence(timeout: 4))
        XCTAssertTrue(app.textViews["macShadowCommandText"].exists)
        XCTAssertTrue(app.buttons["macVoiceButton"].exists)
        XCTAssertTrue(app.buttons["macGenerateButton"].exists)

        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("k", modifierFlags: .command)

        XCTAssertTrue(element(identifier: "macCommandPanel").waitForExistence(timeout: 4))
    }

    func testMinePageShowsControlPlaneSections() throws {
        XCTAssertTrue(app.staticTexts["WORK"].waitForExistence(timeout: 8))
        app.buttons["我的"].tap()

        XCTAssertTrue(app.staticTexts["我的"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["GitHub"].exists)
        XCTAssertTrue(app.staticTexts["Shadow"].exists)
        XCTAssertTrue(app.staticTexts["Life OS"].exists)
        XCTAssertTrue(app.staticTexts["Safety"].exists)
        XCTAssertTrue(staticText(containing: "confirm before write").exists)
        XCTAssertTrue(staticText(containing: "confirmation required").exists)
    }

    func testCommandPanelGeneratesConfirmationGatedIssueFromSelectedRepo() throws {
        XCTAssertTrue(app.staticTexts["WORK"].waitForExistence(timeout: 8))
        tapElement(identifier: "macRepoCard-smart-shadow")
        XCTAssertTrue(staticText(containing: "Verify macOS three-column shadow console.").waitForExistence(timeout: 4))

        element(identifier: "shadowOrb").tap()
        XCTAssertTrue(element(identifier: "macCommandPanel").waitForExistence(timeout: 4))

        let commandText = app.textViews["macShadowCommandText"]
        XCTAssertTrue(commandText.exists)
        commandText.tap()
        commandText.typeText("Create an issue to review the macOS visual console polish")

        app.buttons["macGenerateButton"].tap()

        XCTAssertTrue(app.staticTexts["Confirmation required"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["macConfirmExecuteButton"].exists)
        XCTAssertTrue(staticText(containing: "Create issue in smart-shadow").exists)
    }

    private func tapElement(identifier: String, timeout: TimeInterval = 6) {
        let item = element(identifier: identifier)
        XCTAssertTrue(item.waitForExistence(timeout: timeout), "Expected \(identifier) to exist")
        item.tap()
    }

    private func element(identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func staticText(containing text: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
