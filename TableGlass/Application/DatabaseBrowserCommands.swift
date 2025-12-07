import SwiftUI
#if os(macOS)
import AppKit
#endif

struct DatabaseBrowserCommandActions {
    let runQuery: @MainActor @Sendable () -> Void
    let showHistory: @MainActor @Sendable () -> Void
    let showQuickOpen: @MainActor @Sendable () -> Void
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

            Button("Quick Open Resource") {
                if let action = commandActions?.showQuickOpen {
                    action()
                } else {
                    #if os(macOS)
                    NotificationCenter.default.post(
                        name: .databaseBrowserQuickOpenRequested,
                        object: NSApp.keyWindow
                    )
                    #endif
                }
            }
            .keyboardShortcut("P", modifiers: [.command])
            .disabled(isQuickOpenDisabled)

            Button("Open Connection Window") {
                openWindow(id: SceneID.connectionManagement.rawValue)
            }
            .keyboardShortcut("C", modifiers: [.command, .shift])
        }
    }

    private var isQuickOpenDisabled: Bool {
        #if os(macOS)
        if let window = NSApp.keyWindow, window.title == "Database Browser" {
            return false
        }
        #endif
        return commandActions == nil
    }
}

extension Notification.Name {
    static let databaseBrowserQuickOpenRequested = Notification.Name("databaseBrowser.quickOpenRequested")
}
