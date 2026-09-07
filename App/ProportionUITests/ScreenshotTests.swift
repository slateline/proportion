import XCTest

/// Walks every screen and attaches a screenshot at each stop. CI exports the
/// attachments from the result bundle, so the screens can be reviewed from a
/// machine that can't run the simulator.
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(extraArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + extraArguments
        app.launch()
    }

    private func snap(_ name: String) {
        // Let animations settle so the frame is representative.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tab(_ name: String) {
        dismissKeyboardIfNeeded()
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "tab \(name)")
        button.tap()
    }

    /// The keyboard covers the tab bar; a swipe on the content dismisses it.
    private func dismissKeyboardIfNeeded() {
        guard app.keyboards.count > 0 else { return }
        app.swipeDown()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    private func firstRecipeCard() -> XCUIElement {
        let card = app.descendants(matching: .any).matching(identifier: "recipe-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "a recipe card")
        return card
    }

    // MARK: Light mode walkthrough

    func test01_LightWalkthrough() {
        launch()

        tab("Library")
        _ = firstRecipeCard()
        snap("01-library")

        firstRecipeCard().tap()
        let increment = app.buttons["servings-increment"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        snap("02-recipe-detail")

        for _ in 0..<4 { increment.tap() }
        snap("03-recipe-detail-scaled-to-8")

        app.swipeUp()
        snap("04-recipe-detail-method")

        app.navigationBars.buttons.element(boundBy: 0).tap()

        tab("Search")
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        snap("05-search-empty")
        input.tap()
        input.typeText("high protein dinner, no dairy, under 30 minutes")
        app.buttons["search-send"].tap()
        let results = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'in your library'")).firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: 10), "search results header")
        snap("06-search-results")

        input.tap()
        input.typeText("actually no shellfish either")
        app.buttons["search-send"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        snap("07-search-refined")

        tab("Capture")
        snap("08-capture")

        tab("Settings")
        snap("09-settings")
        app.swipeUp()
        snap("10-settings-privacy")

        tab("Library")
        // Toolbar buttons don't reliably carry accessibility identifiers in
        // SwiftUI; the label works everywhere.
        let newButton = app.buttons["library-new"].exists ? app.buttons["library-new"] : app.buttons["New recipe"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5), "new recipe button")
        newButton.tap()
        let cancel = app.buttons["editor-cancel"].exists ? app.buttons["editor-cancel"] : app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        snap("11-editor-blank")
        cancel.tap()
    }

    // MARK: Dark mode

    func test02_DarkMode() {
        launch(extraArguments: ["-ui-testing-dark"])

        tab("Library")
        _ = firstRecipeCard()
        snap("12-library-dark")

        firstRecipeCard().tap()
        XCTAssertTrue(app.buttons["servings-increment"].waitForExistence(timeout: 5))
        snap("13-recipe-detail-dark")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        tab("Search")
        let input = app.textFields["search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("quick breakfast")
        app.buttons["search-send"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        snap("14-search-results-dark")
    }

    // MARK: Accessibility text size

    func test03_LargeDynamicType() {
        launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])

        tab("Library")
        _ = firstRecipeCard()
        snap("15-library-accessibility-large")

        firstRecipeCard().tap()
        XCTAssertTrue(app.buttons["servings-increment"].waitForExistence(timeout: 5))
        snap("16-recipe-detail-accessibility-large")
    }
}
