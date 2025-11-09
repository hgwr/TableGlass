//
//  TableGlassApp.swift
//  TableGlass
//
//  Created by Shigeru Hagiwara on 2025/11/09.
//

import SwiftUI

@main
struct TableGlassApp: App {
    @StateObject private var environment = AppEnvironment.makeDefault()

    var body: some Scene {
        WindowGroup {
            ContentView(environment: environment)
        }
    }
}
