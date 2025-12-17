//
//  SidebarView.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import SwiftUI

/// Sidebar view displaying list of database connections
struct SidebarView: View {
    @Binding var connections: [DatabaseConnection]
    @Binding var selectedConnection: DatabaseConnection?
    
    @State private var isShowingNewConnectionSheet = false
    @State private var connectionToEdit: DatabaseConnection?
    @State private var newConnection = DatabaseConnection(name: "")
    
    var body: some View {
        List(selection: $selectedConnection) {
            Section("Connections") {
                if connections.isEmpty {
                    emptyState
                } else {
                    ForEach(connections) { connection in
                        ConnectionRow(connection: connection)
                            .tag(connection)
                            .contextMenu {
                                Button("Edit...") {
                                    connectionToEdit = connection
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    deleteConnection(connection)
                                }
                            }
                    }
                    .onDelete(perform: deleteConnections)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
        .toolbar {
            ToolbarItemGroup {
                Button(action: { isShowingNewConnectionSheet = true }) {
                    Label("Add Connection", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingNewConnectionSheet) {
            ConnectionFormView(
                connection: $newConnection,
                isNew: true,
                onSave: { connection in
                    connections.append(connection)
                    selectedConnection = connection
                    newConnection = DatabaseConnection(name: "")
                }
            )
        }
        .sheet(item: $connectionToEdit) { connection in
            ConnectionFormView(
                connection: bindingForConnection(connection),
                isNew: false,
                onSave: { updated in
                    if let index = connections.firstIndex(where: { $0.id == updated.id }) {
                        connections[index] = updated
                        if selectedConnection?.id == updated.id {
                            selectedConnection = updated
                        }
                    }
                },
                onDelete: {
                    deleteConnection(connection)
                }
            )
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.title)
                .foregroundStyle(.tertiary)
            
            Text("No Connections")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button("Add Connection") {
                isShowingNewConnectionSheet = true
            }
            .buttonStyle(.link)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    // MARK: - Actions
    
    private func deleteConnection(_ connection: DatabaseConnection) {
        if selectedConnection?.id == connection.id {
            selectedConnection = nil
        }
        connections.removeAll { $0.id == connection.id }
    }
    
    private func deleteConnections(at offsets: IndexSet) {
        if let selected = selectedConnection,
           let index = connections.firstIndex(of: selected),
           offsets.contains(index) {
            selectedConnection = nil
        }
        connections.remove(atOffsets: offsets)
    }
    
    private func bindingForConnection(_ connection: DatabaseConnection) -> Binding<DatabaseConnection> {
        Binding(
            get: { connections.first { $0.id == connection.id } ?? connection },
            set: { newValue in
                if let index = connections.firstIndex(where: { $0.id == connection.id }) {
                    connections[index] = newValue
                }
            }
        )
    }
}

/// Row view for a single database connection
struct ConnectionRow: View {
    let connection: DatabaseConnection
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: connection.type.iconName)
                .foregroundStyle(connection.type.themeColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.body)
                    .lineLimit(1)
                
                Text(connection.host.isEmpty ? connection.database : connection.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SidebarView(
        connections: .constant(DatabaseConnection.sampleConnections),
        selectedConnection: .constant(nil)
    )
    .frame(width: 250, height: 400)
}

