//
//  ConnectionListView.swift
//  TableProMobile
//

import SwiftUI
import TableProModels

struct ConnectionListView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddConnection = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.connections.isEmpty {
                    emptyState
                } else {
                    connectionList
                }
            }
            .navigationTitle("Connections")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddConnection = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddConnection) {
                ConnectionFormView { connection in
                    appState.addConnection(connection)
                    showingAddConnection = false
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Connections", systemImage: "server.rack")
        } description: {
            Text("Add a database connection to get started.")
        } actions: {
            Button("Add Connection") {
                showingAddConnection = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var connectionList: some View {
        List {
            ForEach(appState.connections) { connection in
                NavigationLink(value: connection) {
                    ConnectionRow(connection: connection)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    appState.removeConnection(appState.connections[index])
                }
            }
        }
        .navigationDestination(for: DatabaseConnection.self) { connection in
            ConnectedView(connection: connection)
        }
    }
}

struct ConnectionRow: View {
    let connection: DatabaseConnection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: connection.type))
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name.isEmpty ? connection.host : connection.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text("\(connection.type.rawValue) — \(connection.host):\(connection.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func iconName(for type: DatabaseType) -> String {
        switch type {
        case .mysql, .mariadb: return "cylinder"
        case .postgresql, .redshift: return "elephant"
        case .sqlite: return "doc"
        case .redis: return "key"
        default: return "server.rack"
        }
    }
}

extension DatabaseConnection: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DatabaseConnection, rhs: DatabaseConnection) -> Bool {
        lhs.id == rhs.id
    }
}
