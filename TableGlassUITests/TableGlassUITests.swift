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
        let app = makeApplication()
        app.launch()

        let form = element(withIdentifier: "connectionManagement.form", in: app)
        XCTAssertTrue(form.waitForExistence(timeout: 5))

        let connectButton = app.buttons["connectionManagement.connectButton"]
        XCTAssertTrue(connectButton.exists)
    }

    @MainActor
    func testConnectFromConnectionManagementShowsInlineError() throws {
        let app = makeApplication()
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
        XCTAssertTrue(errorLabel.waitForExistence(timeout: 5))
    }

    @MainActor
    func testConnectionButtonsReachableWithLargeText() throws {
        let app = makeApplication()
        app.launchArguments.append("--uitest-large-type")
        app.launch()

        let form = element(withIdentifier: "connectionManagement.form", in: app)
        XCTAssertTrue(form.waitForExistence(timeout: 5))

        let scrollView = app.scrollViews["connectionManagement.form"]
        if scrollView.exists {
            scrollView.swipeUp()
        }

        let saveButton = app.buttons["connectionManagement.saveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        XCTAssertTrue(saveButton.isHittable)

        let connectButton = app.buttons["connectionManagement.connectButton"]
        XCTAssertTrue(connectButton.waitForExistence(timeout: 2))
        XCTAssertTrue(connectButton.isHittable)
    }

    @MainActor
    func testMenuItemsExposeConnectionWorkflow() throws {
        let app = makeApplication()
        app.launch()

        let menus = app.menuBars
        XCTAssertTrue(menus.menuItems["New Connection..."].waitForExistence(timeout: 1))
        XCTAssertTrue(menus.menuItems["Manage Connections..."].exists)
        XCTAssertTrue(menus.menuItems["New Database Browser Window..."].exists)
    }

    @MainActor
    func testDatabaseMenuCommandsExposeQueryActions() throws {
        let app = makeApplication()
        app.launchArguments.append("--uitest-database-browser")
        app.launch()

        let browserWindow = app.windows["Database Browser"]
        XCTAssertTrue(browserWindow.waitForExistence(timeout: 2))
        browserWindow.click()

        let menus = app.menuBars
        XCTAssertTrue(menus.menuItems["Run Query"].waitForExistence(timeout: 1))
        XCTAssertTrue(menus.menuItems["Show SQL History"].exists)
        XCTAssertTrue(menus.menuItems["Open Connection Window"].exists)

        let editor = app.textViews["databaseBrowser.query.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        editor.click()

        app.typeKey("h", modifierFlags: [.command, .shift])

        let historyField = app.textFields["Search history"]
        XCTAssertTrue(historyField.waitForExistence(timeout: 1))
    }

    private func replaceText(in element: XCUIElement, with text: String) {
        element.click()
        element.typeKey("a", modifierFlags: .command)
        element.typeText(text)
    }

    private func element(withIdentifier identifier: String, in app: XCUIApplication) -> XCUIElement {
        let other = app.otherElements[identifier]
        if other.exists { return other }
        let scroll = app.scrollViews[identifier]
        if scroll.exists { return scroll }
        let anyMatch = app.descendants(matching: .any)[identifier]
        return anyMatch.exists ? anyMatch : other
    }

    @MainActor
    func testDatabaseBrowserTabsRender() throws {
        let app = makeApplication()
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
        let app = makeApplication()
        app.launchArguments.append("--uitest-database-browser")
        app.launch()

        let browserWindow = app.windows["Database Browser"]
        XCTAssertTrue(browserWindow.waitForExistence(timeout: 2))
        browserWindow.click()

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
            makeApplication().launch()
        }
    }

    private func makeApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITESTING"] = "1"
        app.launchArguments.append("--ui-testing")
        return app
    }
}
