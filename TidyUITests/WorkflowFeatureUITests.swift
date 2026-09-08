import XCTest

final class WorkflowFeatureUITests: XCTestCase {
    @MainActor
    func testLocalTextActionPreviewAndInvalidInput() throws {
        continueAfterFailure = false
        let app = makeIsolatedTidyApplication()
        app.launch()
        defer { app.terminate() }
        app.menuBars.menuBarItems["Text"].click()
        app.menuItems["Text Actions…"].click()
        let original = app.textViews["text-action-original"]
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        original.click()
        original.typeText("{\"b\":2,\"a\":1}")
        XCTAssertEqual(original.value as? String, "{\"b\":2,\"a\":1}")
        app.staticTexts["Format JSON"].firstMatch.click()
        app.buttons["text-action-run"].click()
        let result = app.staticTexts["text-action-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let formatted = NSPredicate { _, _ in
            let text = (result.value as? String) ?? result.label
            return text.contains("\"a\" : 1") && text.contains("\"b\" : 2")
        }
        expectation(for: formatted, evaluatedWith: result)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["Replace selection"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Text actions JSON preview"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        original.click()
        original.typeKey("a", modifierFlags: .command)
        original.typeText("{invalid}")
        app.buttons["text-action-run"].click()
        XCTAssertTrue(app.staticTexts["text-action-error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Copy result"].isEnabled)
    }
}
