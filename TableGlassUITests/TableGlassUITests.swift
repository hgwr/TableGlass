//
//  TableGlassUITests.swift
//  TableGlassUITests
//
//  Created by Shigeru Hagiwara on 2025/11/09.
//

import XCTest

final class TableGlassUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testDatabaseBrowserTabsRender() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitest-database-browser")
        app.launch()

        let tabGroup = app.tabGroups["databaseBrowser.tabGroup"]
        XCTAssertTrue(tabGroup.waitForExistence(timeout: 2))

        let tabCount = tabGroup.tabs.count
        let buttonCount = tabGroup.buttons.count
        let radioButtonCount = tabGroup.radioButtons.count
        let debugDescription = app.debugDescription
        let attachment = XCTAttachment(string: "tabs=\(tabCount) buttons=\(buttonCount) radioButtons=\(radioButtonCount)\n\(debugDescription)")
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(tabCount, 1)

        let logButton = app.buttons["databaseBrowser.showLogButton"]
        XCTAssertTrue(logButton.exists)

        let readOnlyToggle = app.switches["databaseBrowser.readOnlyToggle"]
        XCTAssertTrue(readOnlyToggle.exists)
    }

    @MainActor
    func testDatabaseBrowserSidebarNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitest-database-browser")
        app.launch()

        let catalogRow = app.staticTexts["databaseBrowser.sidebar.catalog.main"]
        XCTAssertTrue(catalogRow.waitForExistence(timeout: 2))
        catalogRow.click()

        let namespaceRow = app.staticTexts["databaseBrowser.sidebar.namespace.main.public"]
        XCTAssertTrue(namespaceRow.waitForExistence(timeout: 2))
        namespaceRow.click()

        let tableRow = app.staticTexts["databaseBrowser.sidebar.table.main.public.artists"]
        XCTAssertTrue(tableRow.waitForExistence(timeout: 2))
        tableRow.click()

        let detailTitle = app.staticTexts["databaseBrowser.detailTitle"]
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 1))
        XCTAssertEqual(detailTitle.label, "artists")

        catalogRow.click() // collapse back to verify hide
        XCTAssertFalse(tableRow.isHittable)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
