//
//  TableGlassApp.swift
//  TableGlass
//
//  Created by Shigeru Hagiwara on 2025/11/09.
//

import SwiftUI
import TableGlassKit
#if os(macOS)
import AppKit
#endif

@main
struct TableGlassApp: App {
    @StateObject private var environment: AppEnvironment
    @StateObject private var connectionManagementViewModel: ConnectionManagementViewModel

    init() {
        let environment: AppEnvironment
        let isRunningUITests = ProcessInfo.processInfo.isRunningUITests
        let isBrowserUITest = ProcessInfo.processInfo.arguments.contains(UITestArguments.databaseBrowser.rawValue)

        if isRunningUITests {
            environment = AppEnvironment(dependencies: .preview)
        } else {
            environment = AppEnvironment.makeDefault()
        }
        _environment = StateObject(wrappedValue: environment)
        _connectionManagementViewModel = StateObject(
            wrappedValue: environment.makeConnectionManagementViewModel()
        )

        #if canImport(AppKit)
        if isRunningUITests {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NSApp.activate(ignoringOtherApps: true)
                if isBrowserUITest {
                    NSApp.windows
                        .filter { $0.title == "Connection Management" }
                        .forEach { $0.close() }
                    let browserWindows = NSApp.windows.filter { $0.title == "Database Browser" }
                    if browserWindows.isEmpty {
                        environment.openPreviewDatabaseBrowserWindow()
                    } else {
                        browserWindows.forEach { $0.makeKeyAndOrderFront(nil) }
                    }
                } else {
                    NSApp.windows
                        .filter { $0.title == "Database Browser" }
                        .forEach { $0.close() }
                    if let connectionWindow = NSApp.windows.first(where: { $0.title.contains("Connection Management") }) {
                        connectionWindow.makeKeyAndOrderFront(nil)
                    }
                }
            }
        }
        #endif
    }

    var body: some Scene {
        connectionManagementWindow
        .commands {
            ConnectionWorkflowCommands(
                environment: environment,
                connectionManagementViewModel: connectionManagementViewModel
            )
        }

        databaseBrowserWindow
        uiTestShimWindow
    }
}

extension TableGlassApp {
    fileprivate var connectionManagementWindow: some Scene {
        WindowGroup("Connection Management", id: SceneID.connectionManagement.rawValue) {
            ConnectionManagementView(viewModel: connectionManagementViewModel)
                .environmentObject(environment)
                .frame(minWidth: 640, minHeight: 480)
        }
        .defaultSize(width: 760, height: 520)
    }
}

extension TableGlassApp {
    fileprivate var databaseBrowserWindow: some Scene {
        WindowGroup("Database Browser", id: SceneID.databaseBrowser.rawValue) {
            DatabaseBrowserWindow(viewModel: environment.makeDatabaseBrowserViewModel())
                .environmentObject(environment)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1080, height: 720)
    }

    fileprivate var uiTestShimWindow: some Scene {
        WindowGroup("UITest Shim", id: SceneID.uiTestShim.rawValue) {
            UITestShimView()
        }
        .defaultSize(width: 400, height: 300)
    }
}

@MainActor
private struct ConnectionWorkflowCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let environment: AppEnvironment
    let connectionManagementViewModel: ConnectionManagementViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Connection...") {
                openConnectionManagement(createNew: true)
            }
            .keyboardShortcut("N")

            Button("Manage Connections...") {
                openConnectionManagement(createNew: false)
            }
            .keyboardShortcut("M", modifiers: [.command, .shift])

            Divider()

            Button("New Database Browser Window...") {
                Task {
                    await openDatabaseBrowserWindow()
                }
            }
            .keyboardShortcut("B", modifiers: [.command, .shift])
        }
    }

    private func openConnectionManagement(createNew: Bool) {
        openWindow(id: SceneID.connectionManagement.rawValue)
        if createNew {
            connectionManagementViewModel.startCreatingConnection()
        }
    }

    private func openDatabaseBrowserWindow() async {
        do {
            let profiles = try await environment.dependencies.connectionStore.listConnections()
            if profiles.count == 1, let single = profiles.first {
                try await environment.connectAndOpenBrowser(for: single)
                return
            }

            if let selection = connectionManagementViewModel.selection,
               let selected = profiles.first(where: { $0.id == selection }) {
                try await environment.connectAndOpenBrowser(for: selected)
                return
            }

            openConnectionManagement(createNew: profiles.isEmpty)
            connectionManagementViewModel.presentError(
                profiles.isEmpty
                    ? "No saved connections found. Create one to open a browser window."
                    : "Select a connection to open a Database Browser window."
            )
        } catch {
            openConnectionManagement(createNew: false)
            connectionManagementViewModel.presentError(error.localizedDescription)
        }
    }
}
