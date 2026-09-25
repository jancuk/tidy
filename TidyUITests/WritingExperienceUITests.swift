import XCTest

final class WritingExperienceUITests: XCTestCase {
    @MainActor
    func testDraftResumePreviewAndSave() throws {
        continueAfterFailure = false
        let app = makeIsolatedTidyApplication()
        app.launch()
        defer { app.terminate() }
        app.typeKey("t", modifierFlags: [.command, .shift])
        let start = app.buttons["start-writing"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.click()
        let document = app.textViews["Writing document"]
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        document.click()
        document.typeText("# A small beginning\n\nOne sentence is enough to start.")
        XCTAssertTrue(app.staticTexts["Draft saved on this Mac"].exists)
        app.buttons["Focus"].click()
        XCTAssertTrue(app.buttons["Exit focus"].exists)
        app.buttons["Exit focus"].click()
        app.buttons["Close"].click()
        let resume = app.buttons["Continue draft: A small beginning"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.click()
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        XCTAssertEqual(document.value as? String, "# A small beginning\n\nOne sentence is enough to start.")
        app.radioButtons["Preview"].click()
        XCTAssertTrue(app.staticTexts["One sentence is enough to start."].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Writing room preview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Save note"].click()
        XCTAssertTrue(app.staticTexts["Your library · 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(resume.exists)
        app.buttons["Archive"].click()
        XCTAssertFalse(app.textViews["Quick capture"].exists)
    }
    @MainActor
    func testTemplateFormattingUndoAndPreviewPreserveWriting() throws {
        continueAfterFailure = false
        let app = makeIsolatedTidyApplication()
        app.launch()
        defer { app.terminate() }
        app.typeKey("t", modifierFlags: [.command, .shift])
        let starter = app.buttons["Start journal"]
        XCTAssertTrue(starter.waitForExistence(timeout: 8))
        starter.click()
        let document = app.textViews["Writing document"]
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        XCTAssertTrue((document.value as? String)?.contains("## What's on my mind") == true)
        document.click()
        document.typeKey("a", modifierFlags: .command)
        document.typeText("A thought worth keeping")
        document.typeKey("a", modifierFlags: .command)
        app.buttons["Bold"].click()
        XCTAssertEqual(document.value as? String, "**A thought worth keeping**")
        document.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(document.value as? String, "A thought worth keeping")
        document.typeKey("a", modifierFlags: .command)
        app.buttons["Italic"].click()
        XCTAssertEqual(document.value as? String, "_A thought worth keeping_")
        app.radioButtons["Preview"].click()
        app.radioButtons["Write"].click()
        XCTAssertEqual(document.value as? String, "_A thought worth keeping_")
        app.buttons["Close"].click()
    }

}
