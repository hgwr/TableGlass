//
//  TableGlassApp.swift
//  TableGlass
//
//  Created by Shigeru Hagiwara on 2025/11/09.
//

import SwiftUI

@main
struct TableGlassApp: App {
    @StateObject private var environment: AppEnvironment
    @StateObject private var connectionListViewModel: ConnectionListViewModel
    @StateObject private var connectionManagementViewModel: ConnectionManagementViewModel

    init() {
        let environment = AppEnvironment.makeDefault()
        _environment = StateObject(wrappedValue: environment)
        _connectionListViewModel = StateObject(wrappedValue: environment.makeConnectionListViewModel())
        _connectionManagementViewModel = StateObject(
            wrappedValue: environment.makeConnectionManagementViewModel()
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: connectionListViewModel)
                .environmentObject(environment)
        }

        connectionManagementWindow
    }

    var commands: some Commands {
        ConnectionManagementCommands()
    }
}

private enum SceneID: String {
    case connectionManagement
}

private extension TableGlassApp {
    var connectionManagementWindow: some Scene {
        WindowGroup("Connection Management", id: SceneID.connectionManagement.rawValue) {
            ConnectionManagementView(viewModel: connectionManagementViewModel)
                .environmentObject(environment)
                .frame(minWidth: 640, minHeight: 480)
        }
        .defaultSize(width: 760, height: 520)
    }
}

private struct ConnectionManagementCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Connections") {
            Button("Manage Connections") {
                openWindow(id: SceneID.connectionManagement.rawValue)
            }
            .keyboardShortcut("M", modifiers: [.command, .shift])
        }
    }
}
