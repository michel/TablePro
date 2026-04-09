import Foundation

// MARK: - Table Node

struct ERTableNode: Identifiable {
    let id: UUID
    let tableName: String
    let columns: [ERColumnDisplay]
    var displayColumns: [ERColumnDisplay]
}

struct ERColumnDisplay: Identifiable {
    let id: String
    let name: String
    let dataType: String
    let isPrimaryKey: Bool
    let isForeignKey: Bool
    let isNullable: Bool
}

// MARK: - Edge

enum ERCardinality {
    case manyToOne
}

struct EREdge: Identifiable {
    let id: UUID
    let fkName: String
    let fromTable: String
    let fromColumn: String
    let toTable: String
    let toColumn: String
    let cardinality: ERCardinality
}

// MARK: - Graph

struct ERDiagramGraph {
    var nodes: [ERTableNode]
    var edges: [EREdge]
    var nodeIndex: [String: UUID]

    static let empty = ERDiagramGraph(nodes: [], edges: [], nodeIndex: [:])
}

// MARK: - Graph Builder

enum ERDiagramGraphBuilder {
    static func build(
        allColumns: [String: [ColumnInfo]],
        allForeignKeys: [String: [ForeignKeyInfo]]
    ) -> ERDiagramGraph {
        var nodeIndex: [String: UUID] = [:]
        var nodes: [ERTableNode] = []

        let fkColumnsByTable: [String: Set<String>] = allForeignKeys.mapValues { fks in
            Set(fks.map(\.column))
        }

        for tableName in allColumns.keys.sorted() {
            let id = stableId(for: tableName)
            nodeIndex[tableName] = id

            let columns = allColumns[tableName] ?? []
            let fkColumns = fkColumnsByTable[tableName] ?? []

            let displayColumns = columns.map { col in
                ERColumnDisplay(
                    id: "\(tableName).\(col.name)",
                    name: col.name,
                    dataType: col.dataType,
                    isPrimaryKey: col.isPrimaryKey,
                    isForeignKey: fkColumns.contains(col.name),
                    isNullable: col.isNullable
                )
            }

            nodes.append(ERTableNode(
                id: id,
                tableName: tableName,
                columns: displayColumns,
                displayColumns: displayColumns
            ))
        }

        var edges: [EREdge] = []
        var seenFKNames: Set<String> = []

        for (tableName, fks) in allForeignKeys {
            for fk in fks {
                let edgeKey = "\(tableName).\(fk.name).\(fk.column)"
                guard !seenFKNames.contains(edgeKey) else { continue }
                seenFKNames.insert(edgeKey)

                guard nodeIndex[fk.referencedTable] != nil else { continue }

                edges.append(EREdge(
                    id: stableId(for: edgeKey),
                    fkName: fk.name,
                    fromTable: tableName,
                    fromColumn: fk.column,
                    toTable: fk.referencedTable,
                    toColumn: fk.referencedColumn,
                    cardinality: .manyToOne
                ))
            }
        }

        return ERDiagramGraph(nodes: nodes, edges: edges, nodeIndex: nodeIndex)
    }

    private static func stableId(for name: String) -> UUID {
        let data = Data(name.utf8)
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, byte) in data.enumerated() {
            bytes[i % 16] ^= byte
        }
        // Set UUID version 4 and variant bits for RFC 4122 compliance
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
