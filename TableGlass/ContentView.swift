//
//  ContentView.swift
//  TableGlass
//
//  Created by Shigeru Hagiwara on 2025/11/09.
//

import SwiftUI
import TableGlassKit

struct ContentView: View {
    @ObservedObject private var viewModel: ConnectionListViewModel

    init(viewModel: ConnectionListViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
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

extension ConnectionProfile {
    fileprivate var kindDescription: String {
        switch kind {
        case .postgreSQL:
            "PostgreSQL"
        case .mySQL:
            "MySQL"
        case .sqlite:
            "SQLite"
        }
    }
}

#Preview {
    let environment = AppEnvironment.makePreview()
    return ContentView(viewModel: environment.makeConnectionListViewModel())
        .environmentObject(environment)
}
