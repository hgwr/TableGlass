import Foundation

enum UITestArguments: String {
    case uiTesting = "--ui-testing"
    case databaseBrowser = "--uitest-database-browser"
}

extension ProcessInfo {
    /// Detects whether the app is running under UI tests.
    /// XCTest may not set `XCTestConfigurationFilePath` for the app-under-test,
    /// so we also inspect other hints added by `XCUIApplication`.
    var isRunningUITests: Bool {
        let env = environment
        if env["XCTestConfigurationFilePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
            || env["XCTestBundlePath"] != nil
            || env["UITESTING"] != nil
        {
            return true
        }

        let args = arguments
        return args.contains(UITestArguments.databaseBrowser.rawValue)
            || args.contains(UITestArguments.uiTesting.rawValue)
    }
}
