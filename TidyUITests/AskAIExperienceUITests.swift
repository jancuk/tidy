import XCTest

final class AskAIExperienceUITests: XCTestCase {
    @MainActor
    func testComposerResponseHistoryAndFailure() throws {
        continueAfterFailure = false
        let app = makeIsolatedTidyApplication()
        let question = "Explain a Swift task\n{\"b\":2}"
        let response = "## Keep the UI responsive\n\nLet async work suspend while the interface stays available.\n\n```swift\nlet items = try await service.fetchItems()\n```\n\n| State | Behavior |\n| --- | --- |\n| Loading | Show progress |"
        app.launchEnvironment["TIDY_ASK_AI_TEST_RESPONSES"] = String(decoding: try JSONEncoder().encode([question: response]), as: UTF8.self)
        app.launch()
        defer { app.terminate() }
        app.menuBars.menuBarItems["Text"].click()
        app.menuItems["Ask AI…"].click()
        let composer = app.textViews["ask-ai-composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.click()
        composer.typeText("Explain a Swift task")
        composer.typeKey(.return, modifierFlags: .shift)
        composer.typeText("{\"b\":2}")
        XCTAssertEqual(composer.value as? String, question)
        app.buttons["ask-ai-send"].click()
        XCTAssertTrue(app.buttons["Copy code"].waitForExistence(timeout: 8))
        XCTAssertEqual(composer.value as? String, "")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Ask AI redesigned conversation"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["Edit"].firstMatch.click()
        XCTAssertEqual(composer.value as? String, question)
        app.buttons["Cancel"].click()
        XCTAssertTrue(app.buttons["Copy code"].exists)
        app.buttons["ask-ai-new-chat"].click()
        XCTAssertFalse(app.buttons["Copy code"].exists)
        let history = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ask-ai-chat-")).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        history.click()
        XCTAssertTrue(app.buttons["Copy code"].waitForExistence(timeout: 5))
        composer.click()
        composer.typeText("No fixture exists")
        app.buttons["ask-ai-send"].click()
        XCTAssertTrue(app.otherElements["ask-ai-error"].waitForExistence(timeout: 5) || app.staticTexts["Couldn’t complete the response"].exists)
        XCTAssertTrue(app.buttons["Try again"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Copy code"].exists)
    }
}
