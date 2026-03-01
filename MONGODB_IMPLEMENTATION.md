# MongoDB Support Implementation Tracker

**Issue**: [#80 — Add MongoDB support](https://github.com/datlechin/TablePro/issues/80)
**Status**: In Progress
**Started**: 2026-02-28

## Decisions

| Decision | Choice |
|----------|--------|
| Scope | Full feature parity |
| C Library | mongo-c-driver (libmongoc) via static linking |
| Document Display | Sample + union fields (flat tabular with JSON for nested) |
| Query Language | MongoDB Shell syntax |

## Implementation Phases

### Phase A: Foundation (Data Model + C Bridge)
- [ ] Add `case mongodb = "MongoDB"` to `DatabaseType` enum
- [ ] Add `defaultPort` (27017), `iconName`, `identifierQuote` for MongoDB
- [ ] Add `Theme.mongodbColor` and `themeColor` case
- [ ] Add MongoDB icon asset to asset catalog
- [ ] Update all `switch` statements on `DatabaseType` across codebase
- [ ] Create `CLibMongoc` C bridge module (header, modulemap)
- [ ] Build/obtain static `libmongoc.a` + `libbson.a` for arm64 and x86_64
- [ ] Add static libraries to `Libs/` directory
- [ ] Configure Xcode project linker settings

### Phase B: Connection Layer
- [ ] Create `MongoDBConnection` class (C wrapper, serial DispatchQueue, async/await bridge)
- [ ] Implement connect/disconnect using `mongoc_client_new` / `mongoc_client_destroy`
- [ ] Implement SSL/TLS support via mongoc URI options
- [ ] Implement connection health ping (`{ ping: 1 }` command)
- [ ] Create `MongoDBDriver` class conforming to `DatabaseDriver` protocol
- [ ] Implement `connect()`, `disconnect()`, `testConnection()`
- [ ] Register in `DatabaseDriverFactory.createDriver(for:)`

### Phase C: Schema Operations
- [ ] Implement `fetchDatabases()` — `listDatabases` command
- [ ] Implement `fetchTables()` — `listCollections`, return as `.table` type
- [ ] Implement `fetchColumns(table:)` — sample documents, union field names, infer BSON types
- [ ] Implement `fetchIndexes(table:)` — `listIndexes` command
- [ ] Implement `fetchForeignKeys(table:)` — return empty (N/A for MongoDB)
- [ ] Implement `fetchTableDDL(table:)` — return collection validator JSON if present
- [ ] Implement `fetchTableMetadata(tableName:)` — collStats command
- [ ] Implement `fetchDatabaseMetadata(_:)` — dbStats command
- [ ] Implement `createDatabase(name:charset:collation:)` — implicit creation via inserting into a temp collection
- [ ] Add `ColumnType.init(fromBSONType:)` initializer

### Phase D: Query Execution
- [ ] Implement `execute(query:)` — parse MongoDB shell syntax, dispatch to appropriate operation
- [ ] Implement MongoDB Shell syntax parser (db.collection.find/aggregate/insertOne/updateOne/deleteOne etc.)
- [ ] Implement `fetchRows(query:offset:limit:)` — paginated find with skip/limit
- [ ] Implement `fetchRowCount(query:)` — countDocuments
- [ ] Implement `executeParameterized(query:parameters:)` — map to MongoDB operations
- [ ] Implement `cancelQuery()` — mongoc cancellation
- [ ] Implement `applyQueryTimeout(_:)` — maxTimeMS per operation
- [ ] Implement document-to-flat-row conversion (union fields, JSON-serialize nested objects)

### Phase E: CRUD / Change Tracking
- [ ] Create `MongoDBStatementGenerator` (parallel to `SQLStatementGenerator`)
- [ ] Generate `insertOne` operations from inserted rows
- [ ] Generate `updateOne` operations from cell changes (using `_id` as primary key)
- [ ] Generate `deleteOne` operations from deleted rows (using `_id`)
- [ ] Integrate with `DataChangeManager.generateSQL()` → support MongoDB path
- [ ] Implement transaction support (`beginTransaction`/`commit`/`rollback`) — MongoDB 4.0+

### Phase F: Connection UI
- [ ] Update `ConnectionFormView` — add MongoDB to type picker (already via `DatabaseType.allCases`)
- [ ] Update `defaultPort` helper in ConnectionFormView for MongoDB (27017)
- [ ] Add MongoDB-specific connection string field or `authSource` field if needed
- [ ] Update `ConnectionStorage` deserialization fallback
- [ ] Verify SSH tunnel works with MongoDB connections

### Phase G: Query Editor Adaptations
- [ ] Add MongoDB syntax highlighting rules (or disable SQL highlighting for MongoDB connections)
- [ ] Add MongoDB-specific autocomplete keywords
- [ ] Update `TableQueryBuilder` or create `MongoDBQueryBuilder` for collection browsing

### Phase H: Documentation & Polish
- [ ] Update CHANGELOG.md under [Unreleased]
- [ ] Add `docs/databases/mongodb.mdx` documentation page
- [ ] Add Vietnamese translation `docs/vi/databases/mongodb.mdx`
- [ ] Update keyboard shortcuts docs if applicable
- [ ] Verify all existing tests still pass
- [ ] Add MongoDB-specific tests

## Files to Create
- `TablePro/Core/Database/CLibMongoc/CLibMongoc.h`
- `TablePro/Core/Database/CLibMongoc/module.modulemap`
- `TablePro/Core/Database/MongoDBConnection.swift`
- `TablePro/Core/Database/MongoDBDriver.swift`
- `TablePro/Core/ChangeTracking/MongoDBStatementGenerator.swift`
- `TablePro/Core/Services/MongoDBQueryBuilder.swift`
- `TablePro/Core/Services/MongoDBShellParser.swift`

## Files to Modify
- `TablePro/Models/DatabaseConnection.swift` — `DatabaseType` enum
- `TablePro/Core/Database/DatabaseDriver.swift` — factory + default impls
- `TablePro/Theme/Theme.swift` — color
- `TablePro/Views/Connection/ConnectionFormView.swift` — port defaults
- `TablePro/Core/Services/ColumnType.swift` — BSON type mapping
- `TablePro/Core/ChangeTracking/DataChangeManager.swift` — MongoDB save path
- `TablePro/Core/ChangeTracking/SQLStatementGenerator.swift` — placeholder syntax
- `TablePro/Core/Database/DatabaseManager.swift` — MongoDB-specific post-connect
- `TablePro/Core/Services/TableQueryBuilder.swift` — MongoDB query building
- Various switch statements across the codebase

## Progress Log

| Date | Phase | Description |
|------|-------|-------------|
| 2026-02-28 | — | Project kickoff, codebase exploration complete |
| 2026-02-28 | A | C bridge module (CLibMongoc.h, modulemap, build script) |
| 2026-02-28 | A | DatabaseType.mongodb enum, Theme, ColumnType BSON mapping, all switch fixes |
| 2026-02-28 | B | MongoDBConnection C wrapper with #if canImport(CLibMongoc) stubs |
| 2026-02-28 | B | MongoDBDriver implementing full DatabaseDriver protocol |
| 2026-02-28 | C-D | MongoShellParser, BsonDocumentFlattener, MongoDBQueryBuilder |
| 2026-02-28 | E | MongoDBStatementGenerator + DataChangeManager integration |
| 2026-02-28 | F | ConnectionFormView defaults, DatabaseDriverFactory wired |
| 2026-02-28 | H | docs (EN + VI), CHANGELOG, icon asset entry |
