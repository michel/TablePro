//
//  TypePickerContentView.swift
//  TablePro
//
//  Searchable type picker for structure view column type editing.
//

import SwiftUI

/// Data type categories for type picker
enum DataTypeCategory: String, CaseIterable {
    case numeric = "Numeric"
    case string = "String"
    case dateTime = "Date & Time"
    case binary = "Binary"
    case other = "Other"

    func types(for dbType: DatabaseType) -> [String] {
        switch self {
        case .numeric:
            switch dbType {
            case .mysql, .mariadb:
                return ["TINYINT", "SMALLINT", "MEDIUMINT", "INT", "BIGINT", "DECIMAL", "NUMERIC", "FLOAT", "DOUBLE", "BIT"]
            case .postgresql, .redshift:
                return ["SMALLINT", "INTEGER", "BIGINT", "DECIMAL", "NUMERIC", "REAL", "DOUBLE PRECISION", "SMALLSERIAL", "SERIAL", "BIGSERIAL"]
            case .mssql:
                return ["TINYINT", "SMALLINT", "INT", "BIGINT", "DECIMAL", "NUMERIC", "FLOAT", "REAL", "MONEY", "SMALLMONEY", "BIT"]
            case .oracle:
                return ["NUMBER", "BINARY_FLOAT", "BINARY_DOUBLE", "INTEGER", "SMALLINT", "FLOAT"]
            case .clickhouse:
                return [
                    "UInt8", "UInt16", "UInt32", "UInt64", "UInt128", "UInt256",
                    "Int8", "Int16", "Int32", "Int64", "Int128", "Int256",
                    "Float32", "Float64", "Decimal", "Decimal32", "Decimal64", "Decimal128", "Decimal256", "Bool"
                ]
            case .sqlite:
                return ["INTEGER", "REAL", "NUMERIC"]
            case .duckdb:
                return ["INTEGER", "BIGINT", "HUGEINT", "SMALLINT", "TINYINT", "DOUBLE", "FLOAT", "DECIMAL", "REAL", "NUMERIC"]
            case .mongodb:
                return ["Int32", "Int64", "Double", "Decimal128"]
            case .redis:
                return ["Integer"]
            }
        case .string:
            switch dbType {
            case .mysql, .mariadb:
                return ["CHAR", "VARCHAR", "TINYTEXT", "TEXT", "MEDIUMTEXT", "LONGTEXT"]
            case .postgresql, .redshift:
                return ["CHAR", "VARCHAR", "TEXT"]
            case .mssql:
                return ["CHAR", "VARCHAR", "NCHAR", "NVARCHAR", "TEXT", "NTEXT"]
            case .oracle:
                return ["CHAR", "VARCHAR2", "NCHAR", "NVARCHAR2", "CLOB", "NCLOB", "LONG"]
            case .clickhouse:
                return ["String", "FixedString", "UUID", "IPv4", "IPv6"]
            case .sqlite:
                return ["TEXT"]
            case .duckdb:
                return ["VARCHAR", "TEXT", "CHAR", "BPCHAR"]
            case .mongodb:
                return ["String", "ObjectId", "UUID"]
            case .redis:
                return ["String"]
            }
        case .dateTime:
            switch dbType {
            case .mysql, .mariadb:
                return ["DATE", "TIME", "DATETIME", "TIMESTAMP", "YEAR"]
            case .postgresql, .redshift:
                return ["DATE", "TIME", "TIMESTAMP", "TIMESTAMPTZ", "INTERVAL"]
            case .mssql:
                return ["DATE", "TIME", "DATETIME", "DATETIME2", "SMALLDATETIME", "DATETIMEOFFSET"]
            case .oracle:
                return ["DATE", "TIMESTAMP", "TIMESTAMP WITH TIME ZONE", "TIMESTAMP WITH LOCAL TIME ZONE", "INTERVAL YEAR TO MONTH", "INTERVAL DAY TO SECOND"]
            case .clickhouse:
                return ["Date", "Date32", "DateTime", "DateTime64"]
            case .sqlite:
                return ["DATE", "DATETIME"]
            case .duckdb:
                return ["DATE", "TIME", "TIMESTAMP", "TIMESTAMP WITH TIME ZONE", "INTERVAL"]
            case .mongodb:
                return ["Date", "Timestamp"]
            case .redis:
                return []
            }
        case .binary:
            switch dbType {
            case .mysql, .mariadb:
                return ["BINARY", "VARBINARY", "TINYBLOB", "BLOB", "MEDIUMBLOB", "LONGBLOB"]
            case .postgresql, .redshift:
                return ["BYTEA"]
            case .mssql:
                return ["BINARY", "VARBINARY", "IMAGE"]
            case .oracle:
                return ["BLOB", "RAW", "LONG RAW", "BFILE"]
            case .clickhouse:
                return []
            case .sqlite:
                return ["BLOB"]
            case .duckdb:
                return ["BLOB", "BYTEA"]
            case .mongodb:
                return ["BinData"]
            case .redis:
                return []
            }
        case .other:
            switch dbType {
            case .mysql, .mariadb:
                return ["BOOLEAN", "ENUM", "SET", "JSON"]
            case .postgresql, .redshift:
                return ["BOOLEAN", "UUID", "JSON", "JSONB", "ARRAY", "HSTORE", "INET", "CIDR", "MACADDR", "TSVECTOR", "TSQUERY"]
            case .mssql:
                return ["BIT", "UNIQUEIDENTIFIER", "XML", "SQL_VARIANT", "ROWVERSION", "HIERARCHYID"]
            case .oracle:
                return ["BOOLEAN", "ROWID", "UROWID", "XMLTYPE", "SDO_GEOMETRY"]
            case .clickhouse:
                return ["Array", "Tuple", "Map", "Nested", "JSON", "Nullable", "LowCardinality", "Enum8", "Enum16", "Nothing"]
            case .sqlite:
                return ["BOOLEAN"]
            case .duckdb:
                return ["BOOLEAN", "UUID", "JSON", "LIST", "MAP", "STRUCT", "ENUM", "BIT", "UNION"]
            case .mongodb:
                return ["Boolean", "Object", "Array", "Null", "Regex"]
            case .redis:
                return ["List", "Set", "Sorted Set", "Hash", "Stream"]
            }
        }
    }
}

struct TypePickerContentView: View {
    let databaseType: DatabaseType
    let currentValue: String
    let onCommit: (String) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""

    private static let rowHeight: CGFloat = 22
    private static let sectionHeaderHeight: CGFloat = 28
    private static let searchAreaHeight: CGFloat = 44
    private static let maxTotalHeight: CGFloat = 360

    private var visibleCategories: [DataTypeCategory] {
        DataTypeCategory.allCases.filter { !filteredTypes(for: $0).isEmpty }
    }

    private func filteredTypes(for category: DataTypeCategory) -> [String] {
        let types = category.types(for: databaseType)
        if searchText.isEmpty { return types }
        let query = searchText.lowercased()
        return types.filter { $0.lowercased().contains(query) }
    }

    private var totalFilteredCount: Int {
        visibleCategories.reduce(0) { $0 + filteredTypes(for: $1).count }
    }

    private var listHeight: CGFloat {
        let contentHeight = CGFloat(totalFilteredCount) * Self.rowHeight
            + CGFloat(visibleCategories.count) * Self.sectionHeaderHeight
            + 8
        return min(contentHeight, Self.maxTotalHeight - Self.searchAreaHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search or type...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .onSubmit { commitFreeform() }

            Divider()

            List {
                ForEach(visibleCategories, id: \.self) { category in
                    Section(header: Text(category.rawValue)) {
                        ForEach(filteredTypes(for: category), id: \.self) { type in
                            typeRow(type)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { commitType(type) }
                                .listRowInsets(EdgeInsets(
                                    top: 2, leading: 6, bottom: 2, trailing: 6
                                ))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, Self.rowHeight)
            .frame(height: listHeight)
        }
        .frame(width: 280)
    }

    @ViewBuilder
    private func typeRow(_ type: String) -> some View {
        if type.caseInsensitiveCompare(currentValue) == .orderedSame {
            Text(type)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.tint)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(type)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func commitFreeform() {
        let text = searchText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        onCommit(text)
        onDismiss()
    }

    private func commitType(_ type: String) {
        onCommit(type)
        onDismiss()
    }
}
