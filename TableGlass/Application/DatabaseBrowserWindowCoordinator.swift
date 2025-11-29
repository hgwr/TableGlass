import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class DatabaseBrowserWindowCoordinator: NSObject {
    #if canImport(AppKit)
    private var controllers: [NSWindowController] = []
    #endif

    func openStandaloneWindow(with viewModel: DatabaseBrowserViewModel) {
        #if canImport(AppKit)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        let hostingController = NSHostingController(rootView: DatabaseBrowserWindow(viewModel: viewModel))
        window.title = viewModel.windowTitle
        window.contentViewController = hostingController
        if ProcessInfo.processInfo.isRunningUITests {
            window.setFrame(NSRect(x: 200, y: 200, width: 960, height: 640), display: true)
        } else {
            window.center()
        }
        let windowController = NSWindowController(window: window)
        windowController.showWindow(nil)
        if ProcessInfo.processInfo.arguments.contains(UITestArguments.databaseBrowser.rawValue) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        controllers.append(windowController)
        #else
        // Intentionally left blank for non-macOS platforms.
        #endif
    }
}

#if canImport(AppKit)
extension DatabaseBrowserWindowCoordinator: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        controllers.removeAll { $0.window === window }
    }
}
#endif
