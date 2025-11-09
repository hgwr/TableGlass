//
//  ContentView.swift
//  TableGlass
//
//  Created by Shigeru Hagiwara on 2025/11/09.
//

import SwiftUI
import TableGlassKit

struct ContentView: View {
    @ObservedObject private var environment: AppEnvironment
    @StateObject private var viewModel: ConnectionListViewModel

    init(environment: AppEnvironment) {
        _environment = ObservedObject(wrappedValue: environment)
        _viewModel = StateObject(wrappedValue: environment.makeConnectionListViewModel())
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.connections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "externaldrive.connected.to.line.below")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("No Connections")
                            .font(.title3)
                            .bold()
                        Text("Create a connection to get started.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(viewModel.connections) { connection in
                        VStack(alignment: .leading) {
                            Text(connection.name)
                                .font(.headline)
                            Text(connection.kindDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Connections")
        }
        .task {
            await viewModel.loadConnections()
        }
    }
}

private extension ConnectionProfile {
    var kindDescription: String {
        switch kind {
        case .postgreSQL:
            "PostgreSQL"
        case .mySQL:
            "MySQL"
        case .sqlite:
            "Sqlite"
        }
    }
}

#Preview {
    ContentView(environment: .makePreview())
}
