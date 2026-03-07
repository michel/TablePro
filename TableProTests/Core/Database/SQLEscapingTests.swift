//
//  SQLEscapingTests.swift
//  TableProTests
//
//  Tests for SQLEscaping utility functions
//

import Foundation
import Testing
@testable import TablePro

@Suite("SQL Escaping")
struct SQLEscapingTests {

    // MARK: - escapeStringLiteral Tests

    @Test("Plain string unchanged")
    func testPlainStringUnchanged() {
        let input = "Hello World"
        let result = SQLEscaping.escapeStringLiteral(input)
        #expect(result == "Hello World")
    }

    @Test("Single quotes doubled")
    func testSingleQuotesDoubled() {
        let input = "O'Brien"
        let result = SQLEscaping.escapeStringLiteral(input)
        #expect(result == "O''Brien")
    }

    @Test("Backslashes doubled")
    func testBackslashesDoubled() {
        let input = "C:\\Users\\Test"
        let result = SQLEscaping.escapeStringLiteral(input)
        #expect(result == "C:\\\\Users\\\\Test")
    }

    @Test("Newline escaped")
    func testNewlineEscaped() {
        let input = "Line1\nLine2"
        let result = SQLEscaping.escapeStringLiteral(input)
        #expect(result == "Line1\\nLine2")
    }

    @Test("Carriage return escaped")
    func testCarriageReturnEscaped() {
        let input = "Text\rMore"
        let result = SQLEscaping.escapeStringLiteral(input)
        #expect(result == "Text\\rMore")
    }

    @Test("Tab escaped")
    func testTabEscaped() {
        let input = "Col1\tCol2"
        let result = SQLEscaping.escapeStringLiteral(input)
        #expect(result == "Col1\\tCol2")
    }

    @Test("Null character escaped")
    func testNullCharacterEscaped() {
        let input = "Text\0End"
        let result = SQLEscaping.escapeStringLiteral(input)
        #expect(result == "Text\\0End")
    }

    @Test("Backspace escaped")
    func testBackspaceEscaped() {
        let input = "Text\u{08}End"
        let result = SQLEscaping.escapeStringLiteral(input)
        #expect(result == "Text\\bEnd")
    }

    @Test("Form feed escaped")
    func testFormFeedEscaped() {
        let input = "Text\u{0C}End"
        let result = SQLEscaping.escapeStringLiteral(input)
        #expect(result == "Text\\fEnd")
    }

    @Test("EOF marker escaped")
    func testEOFMarkerEscaped() {
        let input = "Text\u{1A}End"
        let result = SQLEscaping.escapeStringLiteral(input)
        #expect(result == "Text\\ZEnd")
    }

    @Test("Combined special characters")
    func testCombinedSpecialCharacters() {
        let input = "O'Brien\\test\nline2\t\0end"
        let result = SQLEscaping.escapeStringLiteral(input)
        #expect(result == "O''Brien\\\\test\\nline2\\t\\0end")
    }

    @Test("Empty string unchanged")
    func testEmptyStringUnchanged() {
        let input = ""
        let result = SQLEscaping.escapeStringLiteral(input)
        #expect(result == "")
    }

    @Test("Backslash and quote order prevents double-escaping")
    func testBackslashQuoteEscapingOrder() {
        // Verify that backslash+quote produces \\'' and not \\\\'
        let input = "\\'"
        let result = SQLEscaping.escapeStringLiteral(input)
        #expect(result == "\\\\''")
    }

    // MARK: - escapeLikeWildcards Tests

    // MARK: - PostgreSQL/SQLite escapeStringLiteral Tests

    @Test("PostgreSQL: plain string unchanged")
    func testPostgreSQLPlainStringUnchanged() {
        let result = SQLEscaping.escapeStringLiteral("Hello World", databaseType: .postgresql)
        #expect(result == "Hello World")
    }

    @Test("PostgreSQL: single quotes doubled")
    func testPostgreSQLSingleQuotesDoubled() {
        let result = SQLEscaping.escapeStringLiteral("O'Brien", databaseType: .postgresql)
        #expect(result == "O''Brien")
    }

    @Test("PostgreSQL: newlines preserved")
    func testPostgreSQLNewlinesPreserved() {
        let result = SQLEscaping.escapeStringLiteral("Line1\nLine2", databaseType: .postgresql)
        #expect(result == "Line1\nLine2")
    }

    @Test("PostgreSQL: carriage returns preserved")
    func testPostgreSQLCarriageReturnsPreserved() {
        let result = SQLEscaping.escapeStringLiteral("Text\rMore", databaseType: .postgresql)
        #expect(result == "Text\rMore")
    }

    @Test("PostgreSQL: tabs preserved")
    func testPostgreSQLTabsPreserved() {
        let result = SQLEscaping.escapeStringLiteral("Col1\tCol2", databaseType: .postgresql)
        #expect(result == "Col1\tCol2")
    }

    @Test("PostgreSQL: backslashes preserved")
    func testPostgreSQLBackslashesPreserved() {
        let result = SQLEscaping.escapeStringLiteral("C:\\Users\\Test", databaseType: .postgresql)
        #expect(result == "C:\\Users\\Test")
    }

    @Test("PostgreSQL: null bytes stripped")
    func testPostgreSQLNullBytesStripped() {
        let result = SQLEscaping.escapeStringLiteral("Text\0End", databaseType: .postgresql)
        #expect(result == "TextEnd")
    }

    @Test("PostgreSQL: combined special characters")
    func testPostgreSQLCombinedSpecialCharacters() {
        let result = SQLEscaping.escapeStringLiteral("O'Brien\\test\nline2\t\0end", databaseType: .postgresql)
        #expect(result == "O''Brien\\test\nline2\tend")
    }

    @Test("SQLite: newlines preserved")
    func testSQLiteNewlinesPreserved() {
        let result = SQLEscaping.escapeStringLiteral("Line1\nLine2", databaseType: .sqlite)
        #expect(result == "Line1\nLine2")
    }

    @Test("SQLite: backslashes preserved")
    func testSQLiteBackslashesPreserved() {
        let result = SQLEscaping.escapeStringLiteral("path\\to\\file", databaseType: .sqlite)
        #expect(result == "path\\to\\file")
    }

    @Test("SQLite: single quotes doubled")
    func testSQLiteSingleQuotesDoubled() {
        let result = SQLEscaping.escapeStringLiteral("it's", databaseType: .sqlite)
        #expect(result == "it''s")
    }

    // MARK: - escapeLikeWildcards Tests

    @Test("LIKE plain string unchanged")
    func testLikePlainStringUnchanged() {
        let input = "test"
        let result = SQLEscaping.escapeLikeWildcards(input)
        #expect(result == "test")
    }

    @Test("LIKE percent escaped")
    func testLikePercentEscaped() {
        let input = "test%value"
        let result = SQLEscaping.escapeLikeWildcards(input)
        #expect(result == "test\\%value")
    }

    @Test("LIKE underscore escaped")
    func testLikeUnderscoreEscaped() {
        let input = "test_value"
        let result = SQLEscaping.escapeLikeWildcards(input)
        #expect(result == "test\\_value")
    }

    @Test("LIKE backslash escaped")
    func testLikeBackslashEscaped() {
        let input = "test\\value"
        let result = SQLEscaping.escapeLikeWildcards(input)
        #expect(result == "test\\\\value")
    }

    @Test("LIKE combined wildcards")
    func testLikeCombinedWildcards() {
        let input = "test%value_123\\end"
        let result = SQLEscaping.escapeLikeWildcards(input)
        #expect(result == "test\\%value\\_123\\\\end")
    }

    @Test("LIKE empty string unchanged")
    func testLikeEmptyStringUnchanged() {
        let input = ""
        let result = SQLEscaping.escapeLikeWildcards(input)
        #expect(result == "")
    }

    @Test("LIKE backslash and percent order prevents double-escaping")
    func testLikeBackslashPercentEscapingOrder() {
        // Verify that backslash+percent produces \\% and not \\\\%
        let input = "\\%"
        let result = SQLEscaping.escapeLikeWildcards(input)
        #expect(result == "\\\\\\%")
    }

    // MARK: - isTemporalFunction Tests

    @Test("NOW() is recognized as temporal function")
    func nowIsTemporalFunction() {
        #expect(SQLEscaping.isTemporalFunction("NOW()") == true)
    }

    @Test("CURRENT_TIMESTAMP without parens is recognized")
    func currentTimestampNoParens() {
        #expect(SQLEscaping.isTemporalFunction("CURRENT_TIMESTAMP") == true)
    }

    @Test("CURRENT_TIMESTAMP() with parens is recognized")
    func currentTimestampWithParens() {
        #expect(SQLEscaping.isTemporalFunction("CURRENT_TIMESTAMP()") == true)
    }

    @Test("Case-insensitive matching")
    func caseInsensitive() {
        #expect(SQLEscaping.isTemporalFunction("now()") == true)
        #expect(SQLEscaping.isTemporalFunction("Now()") == true)
        #expect(SQLEscaping.isTemporalFunction("cUrDaTe()") == true)
    }

    @Test("Leading/trailing whitespace is trimmed")
    func whitespaceIsTrimmed() {
        #expect(SQLEscaping.isTemporalFunction("  NOW()  ") == true)
    }

    @Test("Non-temporal functions are rejected")
    func nonTemporalRejected() {
        #expect(SQLEscaping.isTemporalFunction("COUNT(*)") == false)
        #expect(SQLEscaping.isTemporalFunction("UPPER(name)") == false)
        #expect(SQLEscaping.isTemporalFunction("hello") == false)
    }

    @Test("Empty string is rejected")
    func emptyStringRejected() {
        #expect(SQLEscaping.isTemporalFunction("") == false)
    }

    @Test("All 18 known temporal functions are recognized")
    func allKnownFunctions() {
        for function in SQLEscaping.temporalFunctionExpressions {
            #expect(SQLEscaping.isTemporalFunction(function) == true)
        }
    }

    @Test("CURDATE, CURTIME, UTC variants recognized")
    func dateTimeVariants() {
        #expect(SQLEscaping.isTemporalFunction("CURDATE()") == true)
        #expect(SQLEscaping.isTemporalFunction("CURTIME()") == true)
        #expect(SQLEscaping.isTemporalFunction("UTC_TIMESTAMP()") == true)
        #expect(SQLEscaping.isTemporalFunction("UTC_DATE()") == true)
        #expect(SQLEscaping.isTemporalFunction("UTC_TIME()") == true)
    }

    @Test("LOCALTIME and LOCALTIMESTAMP variants recognized")
    func localVariants() {
        #expect(SQLEscaping.isTemporalFunction("LOCALTIME") == true)
        #expect(SQLEscaping.isTemporalFunction("LOCALTIME()") == true)
        #expect(SQLEscaping.isTemporalFunction("LOCALTIMESTAMP") == true)
        #expect(SQLEscaping.isTemporalFunction("LOCALTIMESTAMP()") == true)
    }
}
