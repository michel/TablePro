//
//  CreateTableView.swift
//  TablePro
//
//  Simplified table creation interface with inline column editing.
//

import SwiftUI

struct CreateTableView: View {
    @Binding var options: TableCreationOptions
    let connectionId: UUID
    let databaseType: DatabaseType
    let onCancel: () -> Void
    let onCreate: (TableCreationOptions) -> Void

    @State private var showSQLPreview = false
    @State private var validationError: String?

    private let service: CreateTableService

    init(
        options: Binding<TableCreationOptions>,
        connectionId: UUID,
        databaseType: DatabaseType,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (TableCreationOptions) -> Void
    ) {
        self._options = options
        self.connectionId = connectionId
        self.databaseType = databaseType
        self.onCancel = onCancel
        self.onCreate = onCreate
        self.service = CreateTableService(databaseType: databaseType)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Create New Table")
                    .font(.system(size: DesignConstants.FontSize.title3, weight: .semibold))

                Spacer()

                if let error = validationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: DesignConstants.FontSize.caption))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, DesignConstants.Spacing.md)
            .padding(.vertical, DesignConstants.Spacing.sm)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignConstants.Spacing.md) {
                    generalSection

                    if databaseType != .mongodb {
                        columnsSection
                        sqlPreviewSection
                    }
                }
                .padding(DesignConstants.Spacing.md)
            }

            Divider()

            footer
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - General Section

    private var generalSection: some View {
        Form {
            TextField(
                databaseType == .mongodb
                    ? String(localized: "Collection Name")
                    : String(localized: "Table Name"),
                text: $options.tableName
            )

            if databaseType != .sqlite {
                LabeledContent(String(localized: "Database")) {
                    Text(options.databaseName)
                        .foregroundStyle(DesignConstants.Colors.secondaryText)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Columns Section

    private var columnsSection: some View {
        VStack(alignment: .leading, spacing: DesignConstants.Spacing.xs) {
            SectionHeaderView(title: "Columns", count: options.columns.count) {
                HStack(spacing: DesignConstants.Spacing.xs) {
                    Menu {
                        ForEach(ColumnTemplate.allCases) { template in
                            Button(template.rawValue) {
                                addColumnFromTemplate(template)
                            }
                        }
                    } label: {
                        Label("Template", systemImage: "wand.and.stars")
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)

                    Button(action: addColumn) {
                        Label("Add Column", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }

            ColumnTableView(
                columns: $options.columns,
                primaryKeyColumns: $options.primaryKeyColumns,
                databaseType: databaseType,
                onDelete: deleteColumn
            )
        }
    }

    // MARK: - SQL Preview Section

    private var sqlPreviewSection: some View {
        DisclosureGroup(isExpanded: $showSQLPreview) {
            ScrollView {
                Text(service.generatePreviewSQL(options))
                    .font(.system(size: DesignConstants.FontSize.small, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignConstants.Spacing.sm)
            }
            .frame(maxHeight: 200)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(DesignConstants.CornerRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.medium)
                    .stroke(DesignConstants.Colors.border, lineWidth: 0.5)
            )
        } label: {
            HStack {
                Text("SQL Preview")
                    .font(.system(size: DesignConstants.FontSize.title3, weight: .semibold))

                Spacer()

                Button(action: copySQLToClipboard) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Copy SQL")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                onCancel()
            }

            Button(databaseType == .mongodb
                ? String(localized: "Create Collection")
                : String(localized: "Create Table"))
            {
                createTable()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isCreateEnabled)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(DesignConstants.Spacing.sm)
    }

    // MARK: - Validation

    private var isCreateEnabled: Bool {
        if databaseType == .mongodb {
            return !options.tableName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return options.isValid
    }

    // MARK: - Actions

    private func addColumn() {
        let newColumn = ColumnDefinition(
            name: "column_\(options.columns.count + 1)",
            dataType: "VARCHAR",
            length: 255
        )
        options.columns.append(newColumn)
    }

    private func addColumnFromTemplate(_ template: ColumnTemplate) {
        let newColumn = template.createColumn(for: databaseType)
        options.columns.append(newColumn)
    }

    private func deleteColumn(_ column: ColumnDefinition) {
        options.primaryKeyColumns.removeAll { $0 == column.name }
        options.columns.removeAll { $0.id == column.id }
    }

    private func createTable() {
        do {
            try service.validate(options)
            validationError = nil
            onCreate(options)
        } catch {
            validationError = error.localizedDescription
        }
    }

    private func copySQLToClipboard() {
        let sql = service.generatePreviewSQL(options)
        ClipboardService.shared.writeText(sql)
    }
}
