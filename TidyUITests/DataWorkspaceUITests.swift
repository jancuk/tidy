import XCTest

final class DataWorkspaceUITests: XCTestCase {
    @MainActor
    func testSampleFilteringSortingAndReset() throws {
        continueAfterFailure = false
        let app = makeIsolatedTidyApplication()
        app.launch()
        defer { app.terminate() }
        app.menuBars.menuBarItems["Navigate"].click()
        app.menuItems["Tidy Data Workspace"].click()
        app.buttons["Try sample data"].click()
        let controls = app.buttons["dataFilterSort"]
        XCTAssertTrue(controls.waitForExistence(timeout: 10))
        XCTAssertTrue(app.tables.firstMatch.waitForExistence(timeout: 5))
        controls.click()
        let search = app.textFields["Search all columns"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("Avery")
        app.buttons["Add filter"].click()
        app.textFields["Value"].click()
        app.textFields["Value"].typeText("00")
        app.buttons["Add sort"].click()
        let controlsScreenshot = XCTAttachment(screenshot: app.screenshot())
        controlsScreenshot.name = "Tidy Data filter and sort controls"
        controlsScreenshot.lifetime = .keepAlways
        add(controlsScreenshot)
        app.buttons["Apply"].click()
        XCTAssertTrue(app.staticTexts["Rows 1–2 of 2"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tables.firstMatch.tableRows.count, 2)
        XCTAssertFalse(app.buttons["Next page"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Tidy Data filtered native grid"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Reset view"].click()
        XCTAssertTrue(app.staticTexts["Rows 1–4 of 4"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tables.firstMatch.tableRows.count, 4)
    }
}
