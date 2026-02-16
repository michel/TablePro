//
//  SQLKeywordsTests.swift
//  TableProTests
//
//  Tests for SQLKeywords catalog
//

import Foundation
import Testing
@testable import TablePro

@Suite("SQL Keywords")
struct SQLKeywordsTests {

    @Test("Keywords collection not empty")
    func testKeywordsNotEmpty() {
        #expect(!SQLKeywords.keywords.isEmpty)
        #expect(SQLKeywords.keywords.count > 50)
    }

    @Test("Keywords contain essential SQL keywords")
    func testKeywordsContainEssentialKeywords() {
        let essentialKeywords = [
            "SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "JOIN"
        ]

        for keyword in essentialKeywords {
            #expect(SQLKeywords.keywords.contains(keyword),
                   "Missing essential keyword: \(keyword)")
        }
    }

    @Test("All function categories not empty")
    func testFunctionCategoriesNotEmpty() {
        #expect(!SQLKeywords.aggregateFunctions.isEmpty)
        #expect(!SQLKeywords.dateTimeFunctions.isEmpty)
        #expect(!SQLKeywords.stringFunctions.isEmpty)
        #expect(!SQLKeywords.numericFunctions.isEmpty)
        #expect(!SQLKeywords.nullFunctions.isEmpty)
        #expect(!SQLKeywords.conversionFunctions.isEmpty)
        #expect(!SQLKeywords.windowFunctions.isEmpty)
        #expect(!SQLKeywords.jsonFunctions.isEmpty)
    }

    @Test("allFunctions combines all categories")
    func testAllFunctionsCombinesCategories() {
        let expectedCount =
            SQLKeywords.aggregateFunctions.count +
            SQLKeywords.dateTimeFunctions.count +
            SQLKeywords.stringFunctions.count +
            SQLKeywords.numericFunctions.count +
            SQLKeywords.nullFunctions.count +
            SQLKeywords.conversionFunctions.count +
            SQLKeywords.windowFunctions.count +
            SQLKeywords.jsonFunctions.count

        #expect(SQLKeywords.allFunctions.count == expectedCount)
    }

    @Test("keywordItems returns correct count and kind")
    func testKeywordItemsCorrectness() {
        let items = SQLKeywords.keywordItems()

        #expect(items.count == SQLKeywords.keywords.count)

        for item in items {
            #expect(item.kind == .keyword)
        }
    }

    @Test("functionItems returns correct kind")
    func testFunctionItemsCorrectKind() {
        let items = SQLKeywords.functionItems()

        #expect(items.count == SQLKeywords.allFunctions.count)

        for item in items {
            #expect(item.kind == .function)
        }
    }

    @Test("operatorItems returns correct kind")
    func testOperatorItemsCorrectKind() {
        let items = SQLKeywords.operatorItems()

        #expect(items.count == SQLKeywords.operators.count)

        for item in items {
            #expect(item.kind == .operator)
        }
    }

    @Test("No duplicate function names in allFunctions")
    func testNoDuplicateFunctionNames() {
        let functionNames = SQLKeywords.allFunctions.map { $0.name }
        let uniqueNames = Set(functionNames)

        #expect(functionNames.count == uniqueNames.count,
               "Found \(functionNames.count - uniqueNames.count) duplicate function names")
    }
}
