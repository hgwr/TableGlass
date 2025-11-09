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

    init() {
        let environment = AppEnvironment.makeDefault()
        _environment = StateObject(wrappedValue: environment)
        _connectionListViewModel = StateObject(wrappedValue: environment.makeConnectionListViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: connectionListViewModel)
                .environmentObject(environment)
        }
    }
}
