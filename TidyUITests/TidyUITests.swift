import XCTest

final class TidyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testExample() throws {
        let app = makeIsolatedTidyApplication()
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.menuBars.menuBarItems["Text"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            makeIsolatedTidyApplication().launch()
        }
    }
}
