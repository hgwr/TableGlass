//
//  TableGlassUITests.swift
//  TableGlassUITests
//
//  Created by Shigeru Hagiwara on 2025/11/09.
//

import XCTest

final class TableGlassUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsConnectionManagementForm() throws {
        let app = XCUIApplication()
        app.launch()

        let form = app.otherElements["connectionManagement.form"]
        XCTAssertTrue(form.waitForExistence(timeout: 2))

        let connectButton = app.buttons["connectionManagement.connectButton"]
        XCTAssertTrue(connectButton.exists)
    }

    @MainActor
    func testConnectFromConnectionManagementShowsInlineError() throws {
        let app = XCUIApplication()
        app.launch()

        let nameField = app.textFields["Display Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        replaceText(in: nameField, with: "UI Test Connection")

        let hostField = app.textFields["Host"]
        replaceText(in: hostField, with: "localhost")

        let usernameField = app.textFields["Username"]
        replaceText(in: usernameField, with: "uitest")

        app.buttons["connectionManagement.connectButton"].click()

        let errorLabel = app.staticTexts["connectionManagement.errorMessage"]
        XCTAssertTrue(errorLabel.waitForExistence(timeout: 3))
    }

    @MainActor
    func testMenuItemsExposeConnectionWorkflow() throws {
        let app = XCUIApplication()
        app.launch()

        let menus = app.menuBars
        XCTAssertTrue(menus.menuItems["New Connection..."].waitForExistence(timeout: 1))
        XCTAssertTrue(menus.menuItems["Manage Connections..."].exists)
        XCTAssertTrue(menus.menuItems["New Database Browser Window..."].exists)
    }

    private func replaceText(in element: XCUIElement, with text: String) {
        element.click()
        element.typeKey("a", modifierFlags: .command)
        element.typeText(text)
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
