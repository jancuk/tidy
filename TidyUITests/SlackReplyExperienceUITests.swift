import XCTest

final class SlackReplyExperienceUITests: XCTestCase {
    @MainActor
    func testReviewedReplyAndConfigurableDestinationUseOnlyMockWriter() throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SlackSendUI-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = makeIsolatedTidyApplication()
        app.launchEnvironment["TIDY_SLACK_REPLY_FIXTURE"] = "1"
        app.launchEnvironment["TIDY_PREVIEW_NOTIFICATION_CACHE"] = directory.path
        app.launch()
        defer { app.terminate() }
        app.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["Use Keep it concise"].waitForExistence(timeout: 8))
        app.buttons["Use Keep it concise"].click()
        let editor = app.textViews["slack-send-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["slack-confirm-send"].exists)
        app.buttons["slack-review-message"].click()
        XCTAssertTrue(app.buttons["slack-confirm-send"].waitForExistence(timeout: 5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("slack-outbox.json").path))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Slack send review — mock destination"
        capture.lifetime = .keepAlways
        add(capture)
        app.buttons["Back to edit"].click()
        editor.click(); editor.typeKey("a", modifierFlags: .command)
        editor.typeText("Tidy local test: reviewed reply.")
        app.checkBoxes["slack-other-destination"].click()
        let destination = app.textFields["slack-send-channel"]
        destination.click(); destination.typeText("DLOCALTEST")
        app.buttons["slack-review-message"].click()
        XCTAssertTrue(app.staticTexts["Tidy local test: reviewed reply."].waitForExistence(timeout: 5))
        app.buttons["slack-confirm-send"].click()
        XCTAssertTrue(app.staticTexts["slack-delivery-result"].waitForExistence(timeout: 5))
        app.buttons["Done"].click()
        let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("slack-outbox.json"))) as! [[String: Any]]
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["state"] as? String, "sent")
        let request = rows[0]["request"] as! [String: Any]
        XCTAssertEqual(request["channelID"] as? String, "DLOCALTEST")
        XCTAssertEqual(request["text"] as? String, "Tidy local test: reviewed reply.")
        XCTAssertNil(request["threadTS"])
        app.buttons["slack-new-message"].click()
        XCTAssertTrue(app.textFields["slack-send-channel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["slack-review-message"].isEnabled)
        app.buttons["Cancel"].click()
    }

    @MainActor
    func testLocalSuggestionsRefineClearRestoreAndDailyRecap() throws {
        continueAfterFailure = false
        let app = makeIsolatedTidyApplication()
        app.launchEnvironment["TIDY_SLACK_REPLY_FIXTURE"] = "1"
        app.launch()
        defer { app.terminate() }
        app.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["The conversation so far"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Copy Keep it concise"].exists)
        XCTAssertTrue(app.buttons["Copy Clarify the next step"].exists)
        XCTAssertFalse(app.buttons["Send"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Slack reply inbox — local fixtures only"
        capture.lifetime = .keepAlways
        add(capture)
        let custom = app.descendants(matching: .any)["slack-custom-instruction"].firstMatch
        if !custom.isHittable { app.scrollViews["slack-reply-detail"].scroll(byDeltaX: 0, deltaY: -600) }
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()
        custom.typeText("Ask a clarifying question in Indonesian")
        app.buttons["slack-custom-generate"].click()
        XCTAssertTrue(app.buttons["Copy Custom reply"].waitForExistence(timeout: 5))
        app.scrollViews["slack-reply-detail"].scroll(byDeltaX: 0, deltaY: 1200)
        app.buttons["slack-clear-topic"].click()
        app.buttons["Slack Cleared"].click()
        XCTAssertTrue(app.buttons["slack-clear-topic"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Copy Keep it concise"].exists)
        app.buttons["slack-clear-topic"].click()
        app.buttons["Slack Inbox"].click()
        app.buttons["Slack Insights"].click()
        XCTAssertTrue(app.staticTexts["See how the day unfolded."].waitForExistence(timeout: 5))
        app.buttons["Summarize day"].click()
        XCTAssertTrue(app.staticTexts["Discussion highlights"].waitForExistence(timeout: 5))
        app.buttons["Slack reply settings"].click()
        XCTAssertTrue(app.textFields["slack-watch-names"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].click()
    }
}
