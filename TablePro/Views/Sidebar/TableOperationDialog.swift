//
//  TableOperationDialog.swift
//  TablePro
//
//  Confirmation dialog for table delete/truncate operations.
//  Provides options for foreign key constraint handling and cascade operations.
//

import SwiftUI

/// Confirmation dialog for table delete/truncate operations
struct TableOperationDialog: View {

    // MARK: - Properties

    @Binding var isPresented: Bool
    let tableName: String
    let operationType: TableOperationType
    let databaseType: DatabaseType
    let onConfirm: (TableOperationOptions) -> Void

    // MARK: - State

    @State private var ignoreForeignKeys = false
    @State private var cascade = false

    // MARK: - Computed Properties

    private var title: String {
        switch operationType {
        case .drop:
            return "Drop table '\(tableName)'"
        case .truncate:
            return "Truncate table '\(tableName)'"
        }
    }

    private var cascadeSupported: Bool {
        // SQLite doesn't support CASCADE
        databaseType != .sqlite
    }

    private var isMultipleTables: Bool {
        tableName.contains("tables")
    }

    private var cascadeDescription: String {
        switch operationType {
        case .drop:
            return "Drop all tables that depend on this table"
        case .truncate:
            if databaseType == .mysql || databaseType == .mariadb {
                return "Not supported for TRUNCATE in MySQL/MariaDB"
            }
            return "Truncate all tables linked by foreign keys"
        }
    }

    private var cascadeDisabled: Bool {
        // MySQL/MariaDB don't support CASCADE for TRUNCATE
        if operationType == .truncate && (databaseType == .mysql || databaseType == .mariadb) {
            return true
        }
        return !cascadeSupported
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.vertical, 16)
                .padding(.horizontal, 20)

            Divider()

            // Options
            VStack(alignment: .leading, spacing: 16) {
                // Note for multiple tables
                if isMultipleTables {
                    Text("Same options will be applied to all selected tables.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                // Ignore foreign key checks
                Toggle(isOn: $ignoreForeignKeys) {
                    Text("Ignore foreign key checks")
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)

                // Cascade option
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $cascade) {
                        Text("Cascade")
                            .font(.system(size: 13))
                    }
                    .toggleStyle(.checkbox)
                    .disabled(cascadeDisabled)

                    Text(cascadeDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
                .opacity(cascadeDisabled ? 0.5 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)

            Divider()

            // Footer buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }

                Spacer()

                Button("OK") {
                    confirmAndDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(12)
        }
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Reset state when dialog opens
            ignoreForeignKeys = false
            cascade = false
        }
        .onExitCommand {
            isPresented = false
        }
    }

    private func confirmAndDismiss() {
        let options = TableOperationOptions(
            ignoreForeignKeys: ignoreForeignKeys,
            cascade: cascadeDisabled ? false : cascade
        )
        onConfirm(options)
        isPresented = false
    }
}

// MARK: - Preview

#Preview("Drop Table - MySQL") {
    TableOperationDialog(
        isPresented: .constant(true),
        tableName: "users",
        operationType: .drop,
        databaseType: .mysql,
        onConfirm: { options in
            print("Options: \(options)")
        }
    )
}

#Preview("Truncate Table - PostgreSQL") {
    TableOperationDialog(
        isPresented: .constant(true),
        tableName: "orders",
        operationType: .truncate,
        databaseType: .postgresql,
        onConfirm: { options in
            print("Options: \(options)")
        }
    )
}

#Preview("Drop Table - SQLite") {
    TableOperationDialog(
        isPresented: .constant(true),
        tableName: "products",
        operationType: .drop,
        databaseType: .sqlite,
        onConfirm: { options in
            print("Options: \(options)")
        }
    )
}
