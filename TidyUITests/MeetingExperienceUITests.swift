import XCTest

final class MeetingExperienceUITests: XCTestCase {
    @MainActor
    func testMeetingWorkspacePreferencesSourcesAndSeparateActions() throws {
        continueAfterFailure = false
        let app = makeIsolatedTidyApplication()
        let root = URL(fileURLWithPath: app.launchEnvironment["TIDY_PREVIEW_HISTORY_DIRECTORY"]!)
        defer { try? FileManager.default.removeItem(at: root) }
        let meetingID = UUID().uuidString
        let chunkID = UUID().uuidString
        let segmentID = chunkID + "-0"
        let source = "Kita rilis beta hari Jumat. Ayu will prepare the release checklist."
        let segment: [String: Any] = ["id": segmentID, "chunkID": chunkID, "start": 761, "end": 773, "speaker": "Call", "text": source]
        let chunk: [String: Any] = ["id": chunkID, "fileName": "fixture.wav", "source": "Call", "start": 750, "duration": 60, "hasSpeechLevelAudio": true, "transcribed": true]
        let summary: [String: Any] = ["overview": "The team agreed to an internal beta on Friday.",
            "decisions": [["text": "Release the beta on Friday.", "segmentIDs": [segmentID]]],
            "actions": [["title": "Prepare the release checklist", "owner": "Ayu", "dueText": "Thursday", "segmentIDs": [segmentID]]],
            "questions": []]
        let record: [String: Any] = ["id": meetingID, "title": "Release planning", "createdAt": Date().timeIntervalSinceReferenceDate,
            "duration": 2292, "mode": "call", "appName": "Google Chrome", "summaryProvider": "codexCLI", "summaryLanguage": "Auto",
            "transcriptionProvider": "localWhisper", "status": "ready", "chunks": [chunk], "segments": [segment], "summary": summary, "savedActionIDs": []]
        func save(_ value: [String: Any]) throws {
            let folder = root.appendingPathComponent("Meetings").appendingPathComponent(value["id"] as! String)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: value).write(to: folder.appendingPathComponent("meeting.json"))
        }
        try save(record)
        var transcriptOnly = record
        let transcriptID = UUID().uuidString
        transcriptOnly["id"] = transcriptID
        transcriptOnly["title"] = "Transcript only"
        transcriptOnly["status"] = "transcribed"
        transcriptOnly["summary"] = nil
        try save(transcriptOnly)
        app.launch()
        defer { app.terminate() }
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        // Keep the toolbar below macOS notification banners during native interaction.
        let titleBar = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.015))
        titleBar.press(forDuration: 0.1, thenDragTo: titleBar.withOffset(CGVector(dx: 0, dy: 180 - window.frame.minY)))
        let meetingsNavigation = app.buttons["Meetings, ⌘⇧M"]
        XCTAssertTrue(meetingsNavigation.waitForExistence(timeout: 5))
        meetingsNavigation.click()
        let history = app.buttons["meetings.history.\(meetingID)"]
        XCTAssertTrue(history.waitForExistence(timeout: 8))
        history.click()
        XCTAssertTrue(app.buttons["meetings.playRecording"].exists)
        XCTAssertFalse(app.popUpButtons["meetings.transcriptionProvider"].exists)
        let citation = app.buttons["meetings.citation.\(segmentID)"].firstMatch
        XCTAssertTrue(citation.waitForExistence(timeout: 5))
        citation.click()
        XCTAssertTrue(app.links["meetings.openTranscript"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[source].exists)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Meeting notes with source transcript"
        evidence.lifetime = .keepAlways
        add(evidence)
        app.links["meetings.openTranscript"].click()
        XCTAssertTrue(app.staticTexts[source].waitForExistence(timeout: 5))
        app.buttons["meetings.tab.Notes"].click()
        app.buttons["Add Prepare the release checklist to Today"].click()
        XCTAssertTrue(app.buttons["Added to Today"].exists)
        let preferences = app.buttons["meetings.preferences"]
        let unobstructed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: preferences)
        XCTAssertEqual(XCTWaiter.wait(for: [unobstructed], timeout: 5), .completed)
        preferences.click()
        XCTAssertTrue(app.staticTexts["Meeting preferences"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.checkBoxes["meetings.detectGoogleMeet"].exists)
        XCTAssertFalse(app.textFields["meetings.summaryModel"].exists)
        app.buttons["Done"].click()
        app.buttons["meetings.history.\(transcriptID)"].click()
        XCTAssertTrue(app.buttons["meetings.createNotes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["meetings.transcribe"].exists)
        app.buttons["meetings.new"].click()
        XCTAssertTrue(app.buttons["meetings.start"].waitForExistence(timeout: 5))
        let notetaker = app.checkBoxes["meetings.notetaker"]
        XCTAssertTrue(notetaker.exists)
        let notetakerIsOn = (notetaker.value as? NSNumber)?.boolValue == true || (notetaker.value as? String) == "1"
        if !notetakerIsOn { notetaker.click() }
        XCTAssertEqual(app.buttons["meetings.start"].label, "Start notetaker")
        notetaker.click()
        XCTAssertEqual(app.buttons["meetings.start"].label, "Start recording")
        notetaker.click()
        XCTAssertFalse(app.buttons["meetings.start"].isEnabled)
        app.buttons["In person"].click()
        app.checkBoxes["meetings.consent"].click()
        XCTAssertTrue(app.buttons["meetings.start"].isEnabled)
        app.buttons["Online call"].click()
        XCTAssertTrue(app.popUpButtons["meetings.callAudioSource"].exists)
        XCTAssertFalse(app.popUpButtons["meetings.captureApp"].exists)
        XCTAssertTrue(app.buttons["meetings.start"].isEnabled)
        app.popUpButtons["meetings.callAudioSource"].click()
        app.menuItems["Selected app"].click()
        XCTAssertTrue(app.popUpButtons["meetings.captureApp"].exists)
        app.popUpButtons["meetings.captureApp"].click()
        app.menuItems["Select an app"].click()
        XCTAssertFalse(app.buttons["meetings.start"].isEnabled)
        app.popUpButtons["meetings.callAudioSource"].click()
        app.menuItems["System audio (Google Meet)"].click()
        XCTAssertTrue(app.buttons["meetings.start"].isEnabled)
        XCTAssertFalse(app.buttons["meetings.createNotes"].exists)
        let setup = XCTAttachment(screenshot: app.screenshot())
        setup.name = "Simplified meeting setup"
        setup.lifetime = .keepAlways
        add(setup)
    }
}
