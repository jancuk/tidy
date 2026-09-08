import XCTest

@MainActor
func makeIsolatedTidyApplication() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["XCTestConfigurationFilePath"] = "TidyUITests"
    app.launchEnvironment["TIDY_PREVIEW_HISTORY_DIRECTORY"] = NSTemporaryDirectory() + "TidyWorkflowUI-\(UUID().uuidString)"
    return app
}
