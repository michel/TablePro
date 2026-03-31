import Foundation

public struct ColumnDefinition: Codable, Sendable {
    public var name: String
    public var dataType: String
    public var isNullable: Bool
    public var defaultValue: String?
    public var isPrimaryKey: Bool
    public var autoIncrement: Bool
    public var comment: String?
    public var unsigned: Bool

    public init(
        name: String,
        dataType: String,
        isNullable: Bool = true,
        defaultValue: String? = nil,
        isPrimaryKey: Bool = false,
        autoIncrement: Bool = false,
        comment: String? = nil,
        unsigned: Bool = false
    ) {
        self.name = name
        self.dataType = dataType
        self.isNullable = isNullable
        self.defaultValue = defaultValue
        self.isPrimaryKey = isPrimaryKey
        self.autoIncrement = autoIncrement
        self.comment = comment
        self.unsigned = unsigned
    }
}

public struct IndexDefinition: Codable, Sendable {
    public var name: String
    public var columns: [String]
    public var isUnique: Bool
    public var indexType: String?

    public init(
        name: String,
        columns: [String],
        isUnique: Bool = false,
        indexType: String? = nil
    ) {
        self.name = name
        self.columns = columns
        self.isUnique = isUnique
        self.indexType = indexType
    }
}

public struct ForeignKeyDefinition: Codable, Sendable {
    public var name: String
    public var columns: [String]
    public var referencedTable: String
    public var referencedColumns: [String]
    public var onDelete: String
    public var onUpdate: String

    public init(
        name: String,
        columns: [String],
        referencedTable: String,
        referencedColumns: [String],
        onDelete: String = "NO ACTION",
        onUpdate: String = "NO ACTION"
    ) {
        self.name = name
        self.columns = columns
        self.referencedTable = referencedTable
        self.referencedColumns = referencedColumns
        self.onDelete = onDelete
        self.onUpdate = onUpdate
    }
}

public struct CreateTableOptions: Codable, Sendable {
    public var engine: String?
    public var charset: String?
    public var collation: String?
    public var ifNotExists: Bool

    public init(
        engine: String? = nil,
        charset: String? = nil,
        collation: String? = nil,
        ifNotExists: Bool = false
    ) {
        self.engine = engine
        self.charset = charset
        self.collation = collation
        self.ifNotExists = ifNotExists
    }
}
