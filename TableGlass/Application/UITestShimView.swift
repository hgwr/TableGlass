import SwiftUI

#if os(macOS)
import AppKit
#endif

struct UITestShimView: View {
    var body: some View {
        VStack(spacing: 12) {
            connectionFormPlaceholder
            Divider()
            browserPlaceholder
        }
        .padding()
        .onAppear {
            #if os(macOS)
            NSApp.windows
                .filter { $0.title == "UITest Shim" }
                .forEach { $0.makeKeyAndOrderFront(nil) }
            #endif
        }
    }

    private var connectionFormPlaceholder: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Connection Form Placeholder")
                Button("Connect") {}
                    .accessibilityIdentifier("connectionManagement.connectButton")
                Text("Test error")
                    .accessibilityIdentifier("connectionManagement.errorMessage")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 120)
        .accessibilityIdentifier("connectionManagement.form")
    }

    private var browserPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Database Browser Placeholder")
            TabView {
                Text("Main Catalog")
                    .tabItem {
                        Label("Main", systemImage: "server.rack")
                    }
            }
            .tabViewStyle(.automatic)
            .accessibilityIdentifier(DatabaseBrowserAccessibility.tabGroup.rawValue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Catalog")
                    .accessibilityIdentifier("databaseBrowser.sidebar.catalog.main")
                Text("Namespace")
                    .accessibilityIdentifier("databaseBrowser.sidebar.namespace.main.public")
                Text("Table")
                    .accessibilityIdentifier("databaseBrowser.sidebar.table.main.public.artists")
            }
        }
    }
}

#Preview {
    UITestShimView()
}
