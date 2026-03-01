//
//  MongoShellParserTests.swift
//  TableProTests
//
//  Tests for MongoShellParser
//

import Foundation
import Testing

@testable import TablePro

@Suite("MongoDB Shell Parser")
struct MongoShellParserTests {

    // MARK: - Find Operations

    @Test("find with empty filter")
    func testFindWithEmptyFilter() throws {
        let op = try MongoShellParser.parse("db.users.find({})")
        if case .find(let collection, let filter, let options) = op {
            #expect(collection == "users")
            #expect(filter == "{}")
            #expect(options.sort == nil)
            #expect(options.skip == nil)
            #expect(options.limit == nil)
        } else {
            Issue.record("Expected .find operation")
        }
    }

    @Test("find with filter")
    func testFindWithFilter() throws {
        let op = try MongoShellParser.parse("db.users.find({\"name\": \"John\"})")
        if case .find(let collection, let filter, _) = op {
            #expect(collection == "users")
            #expect(filter == "{\"name\": \"John\"}")
        } else {
            Issue.record("Expected .find operation")
        }
    }

    @Test("find with projection")
    func testFindWithProjection() throws {
        let op = try MongoShellParser.parse("db.users.find({}, {\"name\": 1})")
        if case .find(let collection, let filter, let options) = op {
            #expect(collection == "users")
            #expect(filter == "{}")
            #expect(options.projection == "{\"name\": 1}")
        } else {
            Issue.record("Expected .find operation")
        }
    }

    @Test("find with chained sort, limit, skip")
    func testFindWithChainedOptions() throws {
        let op = try MongoShellParser.parse("db.users.find({}).sort({\"name\": 1}).limit(10).skip(5)")
        if case .find(let collection, let filter, let options) = op {
            #expect(collection == "users")
            #expect(filter == "{}")
            #expect(options.sort == "{\"name\": 1}")
            #expect(options.limit == 10)
            #expect(options.skip == 5)
        } else {
            Issue.record("Expected .find operation")
        }
    }

    @Test("find with just limit")
    func testFindWithJustLimit() throws {
        let op = try MongoShellParser.parse("db.users.find({}).limit(100)")
        if case .find(let collection, let filter, let options) = op {
            #expect(collection == "users")
            #expect(filter == "{}")
            #expect(options.limit == 100)
            #expect(options.sort == nil)
            #expect(options.skip == nil)
        } else {
            Issue.record("Expected .find operation")
        }
    }

    @Test("bare collection reference treated as find all")
    func testBareCollectionAsFindAll() throws {
        let op = try MongoShellParser.parse("db.users")
        if case .find(let collection, let filter, let options) = op {
            #expect(collection == "users")
            #expect(filter == "{}")
            #expect(options.sort == nil)
            #expect(options.skip == nil)
            #expect(options.limit == nil)
        } else {
            Issue.record("Expected .find operation")
        }
    }

    // MARK: - findOne

    @Test("findOne operation")
    func testFindOne() throws {
        let op = try MongoShellParser.parse("db.users.findOne({\"_id\": \"abc\"})")
        if case .findOne(let collection, let filter) = op {
            #expect(collection == "users")
            #expect(filter == "{\"_id\": \"abc\"}")
        } else {
            Issue.record("Expected .findOne operation")
        }
    }

    // MARK: - Aggregate

    @Test("aggregate operation")
    func testAggregate() throws {
        let op = try MongoShellParser.parse("db.orders.aggregate([{\"$group\": {\"_id\": \"$status\"}}])")
        if case .aggregate(let collection, let pipeline) = op {
            #expect(collection == "orders")
            #expect(pipeline == "[{\"$group\": {\"_id\": \"$status\"}}]")
        } else {
            Issue.record("Expected .aggregate operation")
        }
    }

    // MARK: - Count Operations

    @Test("countDocuments operation")
    func testCountDocuments() throws {
        let op = try MongoShellParser.parse("db.users.countDocuments({})")
        if case .countDocuments(let collection, let filter) = op {
            #expect(collection == "users")
            #expect(filter == "{}")
        } else {
            Issue.record("Expected .countDocuments operation")
        }
    }

    @Test("count as alias for countDocuments")
    func testCountAlias() throws {
        let op = try MongoShellParser.parse("db.users.count({})")
        if case .countDocuments(let collection, let filter) = op {
            #expect(collection == "users")
            #expect(filter == "{}")
        } else {
            Issue.record("Expected .countDocuments operation")
        }
    }

    // MARK: - Write Operations

    @Test("insertOne operation")
    func testInsertOne() throws {
        let op = try MongoShellParser.parse("db.users.insertOne({\"name\": \"John\"})")
        if case .insertOne(let collection, let document) = op {
            #expect(collection == "users")
            #expect(document == "{\"name\": \"John\"}")
        } else {
            Issue.record("Expected .insertOne operation")
        }
    }

    @Test("insertMany operation")
    func testInsertMany() throws {
        let op = try MongoShellParser.parse("db.users.insertMany([{\"name\": \"A\"}, {\"name\": \"B\"}])")
        if case .insertMany(let collection, let documents) = op {
            #expect(collection == "users")
            #expect(documents == "[{\"name\": \"A\"}, {\"name\": \"B\"}]")
        } else {
            Issue.record("Expected .insertMany operation")
        }
    }

    @Test("updateOne operation")
    func testUpdateOne() throws {
        let op = try MongoShellParser.parse("db.users.updateOne({\"_id\": 1}, {\"$set\": {\"name\": \"Jane\"}})")
        if case .updateOne(let collection, let filter, let update) = op {
            #expect(collection == "users")
            #expect(filter == "{\"_id\": 1}")
            #expect(update == "{\"$set\": {\"name\": \"Jane\"}}")
        } else {
            Issue.record("Expected .updateOne operation")
        }
    }

    @Test("updateMany operation")
    func testUpdateMany() throws {
        let op = try MongoShellParser.parse("db.users.updateMany({\"active\": true}, {\"$set\": {\"status\": \"ok\"}})")
        if case .updateMany(let collection, let filter, let update) = op {
            #expect(collection == "users")
            #expect(filter == "{\"active\": true}")
            #expect(update == "{\"$set\": {\"status\": \"ok\"}}")
        } else {
            Issue.record("Expected .updateMany operation")
        }
    }

    @Test("replaceOne operation")
    func testReplaceOne() throws {
        let op = try MongoShellParser.parse("db.users.replaceOne({\"_id\": 1}, {\"name\": \"Jane\"})")
        if case .replaceOne(let collection, let filter, let replacement) = op {
            #expect(collection == "users")
            #expect(filter == "{\"_id\": 1}")
            #expect(replacement == "{\"name\": \"Jane\"}")
        } else {
            Issue.record("Expected .replaceOne operation")
        }
    }

    @Test("deleteOne operation")
    func testDeleteOne() throws {
        let op = try MongoShellParser.parse("db.users.deleteOne({\"_id\": 1})")
        if case .deleteOne(let collection, let filter) = op {
            #expect(collection == "users")
            #expect(filter == "{\"_id\": 1}")
        } else {
            Issue.record("Expected .deleteOne operation")
        }
    }

    @Test("deleteMany operation")
    func testDeleteMany() throws {
        let op = try MongoShellParser.parse("db.users.deleteMany({\"active\": false})")
        if case .deleteMany(let collection, let filter) = op {
            #expect(collection == "users")
            #expect(filter == "{\"active\": false}")
        } else {
            Issue.record("Expected .deleteMany operation")
        }
    }

    // MARK: - FindOneAnd Operations

    @Test("findOneAndUpdate operation")
    func testFindOneAndUpdate() throws {
        let op = try MongoShellParser.parse("db.users.findOneAndUpdate({\"_id\": 1}, {\"$set\": {\"name\": \"Jane\"}})")
        if case .findOneAndUpdate(let collection, let filter, let update) = op {
            #expect(collection == "users")
            #expect(filter == "{\"_id\": 1}")
            #expect(update == "{\"$set\": {\"name\": \"Jane\"}}")
        } else {
            Issue.record("Expected .findOneAndUpdate operation")
        }
    }

    @Test("findOneAndReplace operation")
    func testFindOneAndReplace() throws {
        let op = try MongoShellParser.parse("db.users.findOneAndReplace({\"_id\": 1}, {\"name\": \"Jane\", \"age\": 30})")
        if case .findOneAndReplace(let collection, let filter, let replacement) = op {
            #expect(collection == "users")
            #expect(filter == "{\"_id\": 1}")
            #expect(replacement == "{\"name\": \"Jane\", \"age\": 30}")
        } else {
            Issue.record("Expected .findOneAndReplace operation")
        }
    }

    @Test("findOneAndDelete operation")
    func testFindOneAndDelete() throws {
        let op = try MongoShellParser.parse("db.users.findOneAndDelete({\"_id\": 1})")
        if case .findOneAndDelete(let collection, let filter) = op {
            #expect(collection == "users")
            #expect(filter == "{\"_id\": 1}")
        } else {
            Issue.record("Expected .findOneAndDelete operation")
        }
    }

    // MARK: - Index Operations

    @Test("createIndex with keys only")
    func testCreateIndexKeysOnly() throws {
        let op = try MongoShellParser.parse("db.users.createIndex({\"name\": 1})")
        if case .createIndex(let collection, let keys, let options) = op {
            #expect(collection == "users")
            #expect(keys == "{\"name\": 1}")
            #expect(options == nil)
        } else {
            Issue.record("Expected .createIndex operation")
        }
    }

    @Test("createIndex with options")
    func testCreateIndexWithOptions() throws {
        let op = try MongoShellParser.parse("db.users.createIndex({\"name\": 1}, {\"unique\": true})")
        if case .createIndex(let collection, let keys, let options) = op {
            #expect(collection == "users")
            #expect(keys == "{\"name\": 1}")
            #expect(options == "{\"unique\": true}")
        } else {
            Issue.record("Expected .createIndex operation")
        }
    }

    @Test("dropIndex operation")
    func testDropIndex() throws {
        let op = try MongoShellParser.parse("db.users.dropIndex(\"name_1\")")
        if case .dropIndex(let collection, let indexName) = op {
            #expect(collection == "users")
            #expect(indexName == "\"name_1\"")
        } else {
            Issue.record("Expected .dropIndex operation")
        }
    }

    // MARK: - Other Operations

    @Test("drop collection")
    func testDropCollection() throws {
        let op = try MongoShellParser.parse("db.users.drop()")
        if case .drop(let collection) = op {
            #expect(collection == "users")
        } else {
            Issue.record("Expected .drop operation")
        }
    }

    @Test("runCommand")
    func testRunCommand() throws {
        let op = try MongoShellParser.parse("db.runCommand({\"ping\": 1})")
        if case .runCommand(let command) = op {
            #expect(command == "{\"ping\": 1}")
        } else {
            Issue.record("Expected .runCommand operation")
        }
    }

    @Test("adminCommand")
    func testAdminCommand() throws {
        let op = try MongoShellParser.parse("db.adminCommand({\"ping\": 1})")
        if case .runCommand(let command) = op {
            #expect(command == "{\"ping\": 1}")
        } else {
            Issue.record("Expected .runCommand operation")
        }
    }

    @Test("raw JSON as runCommand")
    func testRawJsonAsRunCommand() throws {
        let op = try MongoShellParser.parse("{\"ping\": 1}")
        if case .runCommand(let command) = op {
            #expect(command == "{\"ping\": 1}")
        } else {
            Issue.record("Expected .runCommand operation")
        }
    }

    @Test("show dbs")
    func testShowDbs() throws {
        let op = try MongoShellParser.parse("show dbs")
        if case .listDatabases = op {
            // pass
        } else {
            Issue.record("Expected .listDatabases operation")
        }
    }

    @Test("show databases")
    func testShowDatabases() throws {
        let op = try MongoShellParser.parse("show databases")
        if case .listDatabases = op {
            // pass
        } else {
            Issue.record("Expected .listDatabases operation")
        }
    }

    @Test("show collections")
    func testShowCollections() throws {
        let op = try MongoShellParser.parse("show collections")
        if case .listCollections = op {
            // pass
        } else {
            Issue.record("Expected .listCollections operation")
        }
    }

    @Test("show tables")
    func testShowTables() throws {
        let op = try MongoShellParser.parse("show tables")
        if case .listCollections = op {
            // pass
        } else {
            Issue.record("Expected .listCollections operation")
        }
    }

    // MARK: - Error Cases

    @Test("empty string throws invalidSyntax")
    func testEmptyStringThrowsInvalidSyntax() {
        #expect(throws: MongoShellParseError.self) {
            _ = try MongoShellParser.parse("")
        }
    }

    @Test("SQL query throws invalidSyntax")
    func testSqlQueryThrowsInvalidSyntax() {
        #expect(throws: MongoShellParseError.self) {
            _ = try MongoShellParser.parse("SELECT * FROM users")
        }
    }

    @Test("unknown method throws unsupportedMethod")
    func testUnknownMethodThrowsUnsupportedMethod() {
        #expect(throws: MongoShellParseError.self) {
            _ = try MongoShellParser.parse("db.users.unknownMethod()")
        }
    }

    @Test("insertOne with no argument throws missingArgument")
    func testInsertOneNoArgThrowsMissingArgument() {
        #expect(throws: MongoShellParseError.self) {
            _ = try MongoShellParser.parse("db.users.insertOne()")
        }
    }

    @Test("updateOne with single argument throws missingArgument")
    func testUpdateOneSingleArgThrowsMissingArgument() {
        #expect(throws: MongoShellParseError.self) {
            _ = try MongoShellParser.parse("db.users.updateOne({\"_id\": 1})")
        }
    }
}
