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
}
