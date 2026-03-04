//
//  ExportServiceRedisTests.swift
//  TableProTests
//
//  Tests for Redis-specific export behavior beyond ExportFormat.availableCases
//  (which is covered in ExportModelsRedisTests).
//
//  NOTE: ExportService.fetchAllQuery is private and cannot be tested directly.
//  The Redis SCAN query generation is internal to ExportService and would require
//  either making it internal or extracting it into a testable helper.
//

import Foundation
import Testing
@testable import TablePro

@Suite("Export Service Redis")
struct ExportServiceRedisTests {
    @Test("Redis format count is three")
    func redisFormatCount() {
        let formats = ExportFormat.availableCases(for: .redis)
        #expect(formats.count == 3)
    }

    @Test("MongoDB formats differ from Redis formats")
    func mongoDBFormatsDifferFromRedis() {
        let redisFormats = ExportFormat.availableCases(for: .redis)
        let mongoFormats = ExportFormat.availableCases(for: .mongodb)
        #expect(redisFormats != mongoFormats)
    }

    @Test("SQL databases include SQL format unlike Redis")
    func sqlDatabasesIncludeSQL() {
        let mysqlFormats = ExportFormat.availableCases(for: .mysql)
        #expect(mysqlFormats.contains(.sql))

        let redisFormats = ExportFormat.availableCases(for: .redis)
        #expect(!redisFormats.contains(.sql))
    }

    @Test("Redis and MySQL share CSV and JSON formats")
    func redisAndMysqlShareCsvJson() {
        let redisFormats = ExportFormat.availableCases(for: .redis)
        let mysqlFormats = ExportFormat.availableCases(for: .mysql)
        #expect(redisFormats.contains(.csv))
        #expect(redisFormats.contains(.json))
        #expect(mysqlFormats.contains(.csv))
        #expect(mysqlFormats.contains(.json))
    }

    @Test("Redis includes XLSX format")
    func redisIncludesXlsx() {
        let formats = ExportFormat.availableCases(for: .redis)
        #expect(formats.contains(.xlsx))
    }
}
