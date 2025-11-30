import SwiftUI

struct DatabaseBrowserCommandActions {
    let runQuery: @MainActor @Sendable () -> Void
    let showHistory: @MainActor @Sendable () -> Void
}

private struct DatabaseBrowserCommandActionsKey: FocusedValueKey {
    typealias Value = DatabaseBrowserCommandActions
}

extension FocusedValues {
    var databaseBrowserCommandActions: DatabaseBrowserCommandActions? {
        get { self[DatabaseBrowserCommandActionsKey.self] }
        set { self[DatabaseBrowserCommandActionsKey.self] = newValue }
    }
}

struct DatabaseBrowserCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.databaseBrowserCommandActions) private var commandActions

    var body: some Commands {
        CommandMenu("Database") {
            Button("Run Query") {
                commandActions?.runQuery()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(commandActions == nil)

            Button("Show SQL History") {
                commandActions?.showHistory()
            }
            .keyboardShortcut("H", modifiers: [.command, .shift])
            .disabled(commandActions == nil)

            Divider()

            Button("Open Connection Window") {
                openWindow(id: SceneID.connectionManagement.rawValue)
            }
            .keyboardShortcut("C", modifiers: [.command, .shift])
        }
    }
}
