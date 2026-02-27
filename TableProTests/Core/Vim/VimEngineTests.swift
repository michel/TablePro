//
//  VimEngineTests.swift
//  TableProTests
//
//  Comprehensive tests for the Vim engine state machine
//

import XCTest
@testable import TablePro

// swiftlint:disable file_length type_body_length

@MainActor
final class VimEngineTests: XCTestCase {
    private var buffer: VimTextBufferMock!
    private var engine: VimEngine!
    private var lastMode: VimMode?
    private var lastCommand: String?

    override func setUp() {
        super.setUp()
        buffer = VimTextBufferMock(text: "hello world\nsecond line\nthird line\n")
        engine = VimEngine(buffer: buffer)
        engine.onModeChange = { [weak self] mode in self?.lastMode = mode }
        engine.onCommand = { [weak self] cmd in self?.lastCommand = cmd }
    }

    // MARK: - Initial State

    func testStartsInNormalMode() {
        XCTAssertEqual(engine.mode, .normal)
    }

    func testModeChangeCallbackNotCalledOnInit() {
        XCTAssertNil(lastMode)
    }

    // MARK: - Mode Transitions: Insert Mode Entry

    func testIEntersInsertMode() {
        XCTAssertTrue(engine.process("i", shift: false))
        XCTAssertEqual(engine.mode, .insert)
        XCTAssertEqual(lastMode, .insert)
    }

    func testAEntersInsertModeAfterCursor() {
        buffer.setSelectedRange(NSRange(location: 2, length: 0))
        _ = engine.process("a", shift: false)
        XCTAssertEqual(engine.mode, .insert)
        XCTAssertEqual(buffer.selectedRange().location, 3)
    }

    func testAAtEndOfBuffer() {
        buffer.setSelectedRange(NSRange(location: buffer.length, length: 0))
        _ = engine.process("a", shift: false)
        XCTAssertEqual(engine.mode, .insert)
        // Should not advance past end
        XCTAssertEqual(buffer.selectedRange().location, buffer.length)
    }

    func testShiftIEntersInsertAtLineStart() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        _ = engine.process("I", shift: true)
        XCTAssertEqual(engine.mode, .insert)
        XCTAssertEqual(buffer.selectedRange().location, 0)
    }

    func testShiftIOnSecondLine() {
        buffer.setSelectedRange(NSRange(location: 15, length: 0)) // In "second line"
        _ = engine.process("I", shift: true)
        XCTAssertEqual(engine.mode, .insert)
        XCTAssertEqual(buffer.selectedRange().location, 12) // Start of "second line\n"
    }

    func testShiftAEntersInsertAtLineEnd() {
        buffer.setSelectedRange(NSRange(location: 2, length: 0))
        _ = engine.process("A", shift: true)
        XCTAssertEqual(engine.mode, .insert)
        // Should be at end of "hello world" (before newline, position 11)
        XCTAssertEqual(buffer.selectedRange().location, 11)
    }

    func testOOpensLineBelow() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        _ = engine.process("o", shift: false)
        XCTAssertEqual(engine.mode, .insert)
        XCTAssertTrue(buffer.text.contains("hello world\n\n"))
    }

    func testShiftOOpensLineAbove() {
        buffer.setSelectedRange(NSRange(location: 15, length: 0)) // In "second line"
        _ = engine.process("O", shift: true)
        XCTAssertEqual(engine.mode, .insert)
        // A newline should be inserted before "second line"
        XCTAssertTrue(buffer.text.contains("hello world\n\nsecond"))
    }

    // MARK: - Mode Transitions: Escape from Insert

    func testEscapeExitsInsertMode() {
        _ = engine.process("i", shift: false)
        XCTAssertTrue(engine.process("\u{1B}", shift: false))
        XCTAssertEqual(engine.mode, .normal)
    }

    func testEscapeFromInsertMovesCursorBack() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        _ = engine.process("i", shift: false)
        _ = engine.process("\u{1B}", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 4)
    }

    func testEscapeFromInsertAtLineStartDoesNotMoveBack() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("i", shift: false)
        _ = engine.process("\u{1B}", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 0)
    }

    func testEscapeFromInsertAtSecondLineStartDoesNotMoveBack() {
        buffer.setSelectedRange(NSRange(location: 12, length: 0)) // Start of "second line"
        _ = engine.process("i", shift: false)
        _ = engine.process("\u{1B}", shift: false)
        // Should NOT move back past line start
        XCTAssertEqual(buffer.selectedRange().location, 12)
    }

    // MARK: - Insert Mode Passthrough

    func testInsertModePassesThroughRegularKeys() {
        _ = engine.process("i", shift: false)
        XCTAssertFalse(engine.process("a", shift: false))
        XCTAssertFalse(engine.process("b", shift: false))
        XCTAssertFalse(engine.process("1", shift: false))
        XCTAssertFalse(engine.process(" ", shift: false))
    }

    func testInsertModeOnlyConsumesEscape() {
        _ = engine.process("i", shift: false)
        XCTAssertTrue(engine.process("\u{1B}", shift: false))
    }

    // MARK: - Mode Transitions: Visual Mode

    func testVEntersVisualMode() {
        _ = engine.process("v", shift: false)
        XCTAssertEqual(engine.mode, .visual(linewise: false))
    }

    func testShiftVEntersVisualLineMode() {
        _ = engine.process("V", shift: true)
        XCTAssertEqual(engine.mode, .visual(linewise: true))
    }

    func testEscapeExitsVisualMode() {
        _ = engine.process("v", shift: false)
        _ = engine.process("\u{1B}", shift: false)
        XCTAssertEqual(engine.mode, .normal)
    }

    func testEscapeExitsVisualLineMode() {
        _ = engine.process("V", shift: true)
        _ = engine.process("\u{1B}", shift: false)
        XCTAssertEqual(engine.mode, .normal)
    }

    func testVTogglesBetweenVisualAndNormal() {
        _ = engine.process("v", shift: false)
        XCTAssertEqual(engine.mode, .visual(linewise: false))
        _ = engine.process("v", shift: false) // Toggle off
        XCTAssertEqual(engine.mode, .normal)
    }

    func testShiftVTogglesVisualLineMode() {
        _ = engine.process("V", shift: true)
        XCTAssertEqual(engine.mode, .visual(linewise: true))
        _ = engine.process("V", shift: true) // Toggle off
        XCTAssertEqual(engine.mode, .normal)
    }

    func testVSwitchesFromLinewiseToCharacterwise() {
        _ = engine.process("V", shift: true)
        XCTAssertEqual(engine.mode, .visual(linewise: true))
        _ = engine.process("v", shift: false)
        XCTAssertEqual(engine.mode, .visual(linewise: false))
    }

    func testShiftVSwitchesFromCharacterwiseToLinewise() {
        _ = engine.process("v", shift: false)
        XCTAssertEqual(engine.mode, .visual(linewise: false))
        _ = engine.process("V", shift: true)
        XCTAssertEqual(engine.mode, .visual(linewise: true))
    }

    // MARK: - Mode Transitions: Command-Line Mode

    func testColonEntersCommandLineMode() {
        _ = engine.process(":", shift: false)
        if case .commandLine(let buf) = engine.mode {
            XCTAssertEqual(buf, ":")
        } else {
            XCTFail("Expected command-line mode")
        }
    }

    func testSlashEntersSearchCommandLine() {
        _ = engine.process("/", shift: false)
        if case .commandLine(let buf) = engine.mode {
            XCTAssertEqual(buf, "/")
        } else {
            XCTFail("Expected command-line mode with / prefix")
        }
    }

    // MARK: - Basic Motions: h, j, k, l

    func testHMovesLeft() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        _ = engine.process("h", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 4)
    }

    func testHDoesNotMovePastLineStart() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("h", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 0)
    }

    func testHDoesNotMovePastSecondLineStart() {
        buffer.setSelectedRange(NSRange(location: 12, length: 0)) // Start of "second line"
        _ = engine.process("h", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 12)
    }

    func testLMovesRight() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("l", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 1)
    }

    func testLDoesNotMovePastLineEnd() {
        // "hello world\n" — last char is at index 10, should not go past
        buffer.setSelectedRange(NSRange(location: 10, length: 0))
        _ = engine.process("l", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 10)
    }

    func testJMovesDown() {
        buffer.setSelectedRange(NSRange(location: 3, length: 0))
        _ = engine.process("j", shift: false)
        let (line, _) = buffer.lineAndColumn(forOffset: buffer.selectedRange().location)
        XCTAssertEqual(line, 1)
    }

    func testJDoesNotMovePastLastLine() {
        // Move to last line
        let lastLineOffset = buffer.offset(forLine: buffer.lineCount - 1, column: 0)
        buffer.setSelectedRange(NSRange(location: lastLineOffset, length: 0))
        _ = engine.process("j", shift: false)
        let (line, _) = buffer.lineAndColumn(forOffset: buffer.selectedRange().location)
        XCTAssertEqual(line, buffer.lineCount - 1)
    }

    func testKMovesUp() {
        buffer.setSelectedRange(NSRange(location: 15, length: 0)) // In "second line"
        _ = engine.process("k", shift: false)
        let (line, _) = buffer.lineAndColumn(forOffset: buffer.selectedRange().location)
        XCTAssertEqual(line, 0)
    }

    func testKDoesNotMovePastFirstLine() {
        buffer.setSelectedRange(NSRange(location: 3, length: 0))
        _ = engine.process("k", shift: false)
        let (line, _) = buffer.lineAndColumn(forOffset: buffer.selectedRange().location)
        XCTAssertEqual(line, 0)
    }

    func testJKPreservesGoalColumn() {
        // Start at column 5 on first line
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        _ = engine.process("j", shift: false) // Down
        _ = engine.process("j", shift: false) // Down again
        _ = engine.process("k", shift: false) // Up
        // Should still be at column 5 on second line
        let (line, col) = buffer.lineAndColumn(forOffset: buffer.selectedRange().location)
        XCTAssertEqual(line, 1)
        XCTAssertEqual(col, 5)
    }

    // MARK: - Line Motions: 0, $

    func testZeroMovesToLineStart() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        _ = engine.process("0", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 0)
    }

    func testZeroOnSecondLine() {
        buffer.setSelectedRange(NSRange(location: 18, length: 0)) // Mid "second line"
        _ = engine.process("0", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 12)
    }

    func testDollarMovesToLineEnd() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("$", shift: false)
        // Last char of "hello world" is at index 10
        XCTAssertEqual(buffer.selectedRange().location, 10)
    }

    // MARK: - Word Motions: w, b, e

    func testWMovesToNextWord() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("w", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 6) // Start of "world"
    }

    func testBMovesToPreviousWord() {
        buffer.setSelectedRange(NSRange(location: 6, length: 0))
        _ = engine.process("b", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 0) // Start of "hello"
    }

    func testEMovesToEndOfWord() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("e", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 4) // End of "hello"
    }

    func testMultipleWMotions() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("w", shift: false) // → "world"
        _ = engine.process("w", shift: false) // → next word
        XCTAssertGreaterThan(buffer.selectedRange().location, 6)
    }

    // MARK: - Document Motions: gg, G

    func testGGMovesToDocumentStart() {
        buffer.setSelectedRange(NSRange(location: 20, length: 0))
        _ = engine.process("g", shift: false)
        _ = engine.process("g", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 0)
    }

    func testGGWithCountGoesToLine() {
        _ = engine.process("2", shift: false)
        _ = engine.process("g", shift: false)
        _ = engine.process("g", shift: false)
        // 2gg → line 2 (0-indexed line 1)
        let (line, _) = buffer.lineAndColumn(forOffset: buffer.selectedRange().location)
        XCTAssertEqual(line, 1)
    }

    func testShiftGMovesToLastLine() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("G", shift: true)
        let (line, _) = buffer.lineAndColumn(forOffset: buffer.selectedRange().location)
        XCTAssertEqual(line, buffer.lineCount - 1)
    }

    func testShiftGWithCountGoesToLine() {
        _ = engine.process("2", shift: false)
        _ = engine.process("G", shift: true)
        // 2G → line 2 (0-indexed line 1)
        let (line, _) = buffer.lineAndColumn(forOffset: buffer.selectedRange().location)
        XCTAssertEqual(line, 1)
    }

    func testGFollowedByNonGIsConsumed() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        _ = engine.process("g", shift: false)
        let consumed = engine.process("x", shift: false) // Not a valid g-combo
        XCTAssertTrue(consumed)
        // Cursor shouldn't have changed meaningfully (unknown g-prefix consumed)
    }

    // MARK: - Count Prefix

    func testCountPrefixWithMotion() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("3", shift: false)
        _ = engine.process("l", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 3)
    }

    func testCountPrefixWithJ() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("2", shift: false)
        _ = engine.process("j", shift: false)
        let (line, _) = buffer.lineAndColumn(forOffset: buffer.selectedRange().location)
        XCTAssertEqual(line, 2)
    }

    func testCountPrefixWithH() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        _ = engine.process("3", shift: false)
        _ = engine.process("h", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 2)
    }

    func testCountPrefixWithW() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("2", shift: false)
        _ = engine.process("w", shift: false)
        // Two word-forward motions from "hello"
        XCTAssertGreaterThan(buffer.selectedRange().location, 6)
    }

    func testMultiDigitCountPrefix() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("1", shift: false)
        _ = engine.process("0", shift: false)
        _ = engine.process("l", shift: false)
        // 10l → move right 10 (clamped to line end)
        XCTAssertEqual(buffer.selectedRange().location, 10)
    }

    func testCountPrefixOverflowIsCapped() {
        // Entering a very large count should not crash
        for _ in 0..<10 {
            _ = engine.process("9", shift: false)
        }
        _ = engine.process("l", shift: false)
        // Should not crash — count is capped at 99999
    }

    func testZeroIsMotionNotCountWhenNoPrefix() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        _ = engine.process("0", shift: false) // Should move to line start, not start count
        XCTAssertEqual(buffer.selectedRange().location, 0)
    }

    func testZeroIsContinuationWhenCountActive() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("1", shift: false)
        _ = engine.process("0", shift: false) // Count = 10
        _ = engine.process("l", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 10)
    }

    // MARK: - Delete Line (dd)

    func testDDDeletesCurrentLine() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("d", shift: false)
        _ = engine.process("d", shift: false)
        XCTAssertFalse(buffer.text.hasPrefix("hello world"))
        XCTAssertTrue(buffer.text.hasPrefix("second line"))
    }

    func testDDDeletesMiddleLine() {
        buffer.setSelectedRange(NSRange(location: 15, length: 0)) // "second line"
        _ = engine.process("d", shift: false)
        _ = engine.process("d", shift: false)
        XCTAssertFalse(buffer.text.contains("second line"))
        XCTAssertTrue(buffer.text.contains("hello world"))
        XCTAssertTrue(buffer.text.contains("third line"))
    }

    func testDDWithCount() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("2", shift: false)
        _ = engine.process("d", shift: false)
        _ = engine.process("d", shift: false)
        // Should delete first two lines
        XCTAssertTrue(buffer.text.hasPrefix("third line"))
    }

    // MARK: - Delete with Motion (dw, d$, d0)

    func testDeleteWord() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("d", shift: false)
        _ = engine.process("w", shift: false)
        XCTAssertTrue(buffer.text.hasPrefix("world"))
    }

    func testDeleteToLineEnd() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        _ = engine.process("d", shift: false)
        _ = engine.process("$", shift: false)
        // Should delete " world" leaving "hello"
        XCTAssertTrue(buffer.text.hasPrefix("hello"))
    }

    func testDeleteToLineStart() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        _ = engine.process("d", shift: false)
        _ = engine.process("0", shift: false)
        // Should delete "hello" leaving " world\n..."
        XCTAssertTrue(buffer.text.hasPrefix(" world"))
    }

    func testDeleteWithJ() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("d", shift: false)
        _ = engine.process("j", shift: false)
        // Should delete first two lines
        XCTAssertTrue(buffer.text.hasPrefix("third line"))
    }

    func testDeleteWithK() {
        buffer.setSelectedRange(NSRange(location: 15, length: 0)) // "second line"
        _ = engine.process("d", shift: false)
        _ = engine.process("k", shift: false)
        // Should delete first two lines
        XCTAssertTrue(buffer.text.hasPrefix("third line"))
    }

    func testDeleteWordWithB() {
        buffer.setSelectedRange(NSRange(location: 6, length: 0)) // Start of "world"
        _ = engine.process("d", shift: false)
        _ = engine.process("b", shift: false)
        // Should delete "hello " leaving "world\n..."
        XCTAssertTrue(buffer.text.hasPrefix("world"))
    }

    func testDeleteToWordEnd() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("d", shift: false)
        _ = engine.process("e", shift: false)
        // Should delete "hello" leaving " world\n..."
        XCTAssertTrue(buffer.text.hasPrefix(" world"))
    }

    // MARK: - Yank Line (yy) and Paste (p, P)

    func testYYYanksLine() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("y", shift: false)
        _ = engine.process("y", shift: false)
        // Text should be unchanged
        XCTAssertTrue(buffer.text.hasPrefix("hello world"))
    }

    func testYYAndPasteBelow() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("y", shift: false)
        _ = engine.process("y", shift: false)
        _ = engine.process("p", shift: false)
        XCTAssertTrue(buffer.text.contains("hello world\nhello world\n"))
    }

    func testYYAndPasteAbove() {
        buffer.setSelectedRange(NSRange(location: 15, length: 0)) // "second line"
        _ = engine.process("y", shift: false)
        _ = engine.process("y", shift: false)
        _ = engine.process("P", shift: true) // Paste above
        XCTAssertTrue(buffer.text.contains("second line\nsecond line\n"))
    }

    func testPasteEmptyRegisterDoesNothing() {
        let originalText = buffer.text
        _ = engine.process("p", shift: false)
        XCTAssertEqual(buffer.text, originalText)
    }

    // MARK: - Characterwise Paste

    func testXThenPRestoresCharacter() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("x", shift: false) // Delete 'h'
        XCTAssertTrue(buffer.text.hasPrefix("ello"))
        _ = engine.process("P", shift: true) // Paste before cursor
        XCTAssertTrue(buffer.text.hasPrefix("hello"))
    }

    // MARK: - Change Line (cc)

    func testCCChangesLine() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("c", shift: false)
        _ = engine.process("c", shift: false)
        XCTAssertEqual(engine.mode, .insert)
        // Line content removed, newline preserved
        XCTAssertTrue(buffer.text.hasPrefix("\n"))
    }

    // MARK: - Change with Motion (cw)

    func testChangeWord() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("c", shift: false)
        _ = engine.process("w", shift: false)
        XCTAssertEqual(engine.mode, .insert)
    }

    // MARK: - Delete Character (x)

    func testXDeletesCharacter() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("x", shift: false)
        XCTAssertTrue(buffer.text.hasPrefix("ello world"))
    }

    func testXWithCount() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("3", shift: false)
        _ = engine.process("x", shift: false)
        XCTAssertTrue(buffer.text.hasPrefix("lo world"))
    }

    func testXAtEndOfBuffer() {
        let emptyBuffer = VimTextBufferMock(text: "a")
        let emptyEngine = VimEngine(buffer: emptyBuffer)
        emptyBuffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = emptyEngine.process("x", shift: false)
        XCTAssertEqual(emptyBuffer.text, "")
    }

    func testXOnEmptyBufferDoesNotCrash() {
        let emptyBuffer = VimTextBufferMock(text: "")
        let emptyEngine = VimEngine(buffer: emptyBuffer)
        _ = emptyEngine.process("x", shift: false)
        XCTAssertEqual(emptyBuffer.text, "")
    }

    // MARK: - Undo

    func testUCallsUndo() {
        // Verify 'u' is consumed in Normal mode
        let consumed = engine.process("u", shift: false)
        XCTAssertTrue(consumed)
    }

    func testRedoMethod() {
        // Verify redo() doesn't crash
        engine.redo()
    }

    // MARK: - Visual Mode Motions

    func testVisualModeExtendsSelectionWithL() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("v", shift: false) // Enter visual
        _ = engine.process("l", shift: false)
        _ = engine.process("l", shift: false)
        let sel = buffer.selectedRange()
        XCTAssertGreaterThan(sel.length, 0)
    }

    func testVisualModeExtendsSelectionWithW() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("v", shift: false)
        _ = engine.process("w", shift: false) // Extend to next word
        let sel = buffer.selectedRange()
        XCTAssertGreaterThan(sel.length, 0)
    }

    func testVisualModeExtendsSelectionWithH() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        _ = engine.process("v", shift: false)
        _ = engine.process("h", shift: false)
        let sel = buffer.selectedRange()
        XCTAssertGreaterThan(sel.length, 0)
    }

    func testVisualModeExtendsSelectionWithJ() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("v", shift: false)
        _ = engine.process("j", shift: false)
        let sel = buffer.selectedRange()
        XCTAssertGreaterThan(sel.length, 0)
    }

    func testVisualModeExtendsSelectionWithK() {
        buffer.setSelectedRange(NSRange(location: 15, length: 0))
        _ = engine.process("v", shift: false)
        _ = engine.process("k", shift: false)
        let sel = buffer.selectedRange()
        XCTAssertGreaterThan(sel.length, 0)
    }

    func testVisualModeExtendsWith0() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        _ = engine.process("v", shift: false)
        _ = engine.process("0", shift: false)
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0)
        XCTAssertGreaterThan(sel.length, 0)
    }

    func testVisualModeExtendsWith$() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("v", shift: false)
        _ = engine.process("$", shift: false)
        let sel = buffer.selectedRange()
        XCTAssertGreaterThan(sel.length, 0)
    }

    func testVisualModeExtendsWithE() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("v", shift: false)
        _ = engine.process("e", shift: false)
        let sel = buffer.selectedRange()
        XCTAssertGreaterThan(sel.length, 0)
    }

    func testVisualModeExtendsWithB() {
        buffer.setSelectedRange(NSRange(location: 6, length: 0))
        _ = engine.process("v", shift: false)
        _ = engine.process("b", shift: false)
        let sel = buffer.selectedRange()
        XCTAssertGreaterThan(sel.length, 0)
    }

    func testVisualModeExtendsWithG() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("v", shift: false)
        _ = engine.process("G", shift: true) // Extend to end
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.length, buffer.length)
    }

    // MARK: - Visual Mode Operations

    func testVisualDeleteSelection() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("v", shift: false)
        _ = engine.process("l", shift: false)
        _ = engine.process("l", shift: false)
        _ = engine.process("d", shift: false)
        XCTAssertEqual(engine.mode, .normal)
        // Some characters should have been deleted
        XCTAssertFalse(buffer.text.hasPrefix("hel"))
    }

    func testVisualXDeletesSelection() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("v", shift: false)
        _ = engine.process("l", shift: false)
        _ = engine.process("x", shift: false) // x in visual = delete
        XCTAssertEqual(engine.mode, .normal)
    }

    func testVisualYankSelection() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("v", shift: false)
        _ = engine.process("e", shift: false)
        _ = engine.process("y", shift: false)
        XCTAssertEqual(engine.mode, .normal)
        // Text should be unchanged after yank
        XCTAssertTrue(buffer.text.hasPrefix("hello world"))
    }

    func testVisualChangeSelection() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("v", shift: false)
        _ = engine.process("e", shift: false)
        _ = engine.process("c", shift: false) // Change
        XCTAssertEqual(engine.mode, .insert)
    }

    func testVisualLineModeSelectsEntireLine() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        _ = engine.process("V", shift: true) // Visual line
        let sel = buffer.selectedRange()
        // Should select the entire first line including newline
        XCTAssertEqual(sel.location, 0)
        XCTAssertEqual(sel.length, 12) // "hello world\n"
    }

    func testVisualLineModeDeleteRemovesFullLines() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("V", shift: true)
        _ = engine.process("d", shift: false)
        XCTAssertEqual(engine.mode, .normal)
        XCTAssertTrue(buffer.text.hasPrefix("second line"))
    }

    // MARK: - Command-Line Mode

    func testCommandLineAccumulatesCharacters() {
        _ = engine.process(":", shift: false)
        _ = engine.process("w", shift: false)
        _ = engine.process("q", shift: false)
        if case .commandLine(let buf) = engine.mode {
            XCTAssertEqual(buf, ":wq")
        } else {
            XCTFail("Expected command-line mode")
        }
    }

    func testCommandLineEnterExecutes() {
        _ = engine.process(":", shift: false)
        _ = engine.process("w", shift: false)
        _ = engine.process("\r", shift: false)
        XCTAssertEqual(lastCommand, "w")
        XCTAssertEqual(engine.mode, .normal)
    }

    func testCommandLineNewlineExecutes() {
        _ = engine.process(":", shift: false)
        _ = engine.process("q", shift: false)
        _ = engine.process("\n", shift: false)
        XCTAssertEqual(lastCommand, "q")
        XCTAssertEqual(engine.mode, .normal)
    }

    func testCommandLineEscapeCancels() {
        _ = engine.process(":", shift: false)
        _ = engine.process("w", shift: false)
        _ = engine.process("\u{1B}", shift: false)
        XCTAssertEqual(engine.mode, .normal)
        XCTAssertNil(lastCommand)
    }

    func testCommandLineBackspaceRemovesChar() {
        _ = engine.process(":", shift: false)
        _ = engine.process("w", shift: false)
        _ = engine.process("q", shift: false)
        _ = engine.process("\u{7F}", shift: false) // Backspace
        if case .commandLine(let buf) = engine.mode {
            XCTAssertEqual(buf, ":w")
        } else {
            XCTFail("Expected command-line mode")
        }
    }

    func testCommandLineBackspaceOnEmptyExits() {
        _ = engine.process(":", shift: false)
        _ = engine.process("\u{7F}", shift: false) // Backspace on ":"
        XCTAssertEqual(engine.mode, .normal)
    }

    func testSearchCommandLineExecutes() {
        _ = engine.process("/", shift: false)
        _ = engine.process("h", shift: false)
        _ = engine.process("i", shift: false)
        _ = engine.process("\r", shift: false)
        XCTAssertEqual(lastCommand, "hi")
    }

    // MARK: - Escape in Normal Mode

    func testEscapeInNormalModeClearsPendingOperator() {
        _ = engine.process("d", shift: false) // Start pending delete
        _ = engine.process("\u{1B}", shift: false)
        // Now 'd' should start a new pending, not dd
        _ = engine.process("d", shift: false)
        XCTAssertTrue(buffer.text.hasPrefix("hello world"))
    }

    func testEscapeInNormalModeClearsCountPrefix() {
        _ = engine.process("5", shift: false)
        _ = engine.process("\u{1B}", shift: false)
        _ = engine.process("l", shift: false)
        // Count was cleared, so only moves 1
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("l", shift: false)
        XCTAssertEqual(buffer.selectedRange().location, 1)
    }

    func testEscapeInNormalModeClearsPendingG() {
        _ = engine.process("g", shift: false)
        _ = engine.process("\u{1B}", shift: false)
        // pendingG should be cleared — next 'g' starts fresh
    }

    // MARK: - Reset

    func testResetClearsPendingState() {
        _ = engine.process("d", shift: false)
        engine.reset()
        XCTAssertEqual(engine.mode, .normal)
        _ = engine.process("d", shift: false)
        XCTAssertTrue(buffer.text.hasPrefix("hello world"))
    }

    func testResetFromInsertMode() {
        _ = engine.process("i", shift: false)
        engine.reset()
        XCTAssertEqual(engine.mode, .normal)
    }

    func testResetFromVisualMode() {
        _ = engine.process("v", shift: false)
        engine.reset()
        XCTAssertEqual(engine.mode, .normal)
    }

    func testResetFromCommandLineMode() {
        _ = engine.process(":", shift: false)
        engine.reset()
        XCTAssertEqual(engine.mode, .normal)
    }

    // MARK: - Operator + Motion Combinations

    func testYankWord() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("y", shift: false)
        _ = engine.process("w", shift: false)
        // Text unchanged
        XCTAssertTrue(buffer.text.hasPrefix("hello world"))
        // Now paste should insert the yanked word
        _ = engine.process("p", shift: false)
        XCTAssertTrue(buffer.text.contains("hhello"))
    }

    func testYankToLineEnd() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        _ = engine.process("y", shift: false)
        _ = engine.process("$", shift: false)
        // Text unchanged, cursor at line start
        XCTAssertEqual(buffer.selectedRange().location, 0)
    }

    func testDeleteBackwardWord() {
        buffer.setSelectedRange(NSRange(location: 6, length: 0)) // Start of "world"
        _ = engine.process("d", shift: false)
        _ = engine.process("b", shift: false)
        XCTAssertTrue(buffer.text.hasPrefix("world"))
    }

    // MARK: - Edge Cases

    func testEmptyBuffer() {
        let emptyBuffer = VimTextBufferMock(text: "")
        let emptyEngine = VimEngine(buffer: emptyBuffer)
        _ = emptyEngine.process("j", shift: false)
        _ = emptyEngine.process("k", shift: false)
        _ = emptyEngine.process("h", shift: false)
        _ = emptyEngine.process("l", shift: false)
        _ = emptyEngine.process("w", shift: false)
        _ = emptyEngine.process("b", shift: false)
        _ = emptyEngine.process("e", shift: false)
        _ = emptyEngine.process("0", shift: false)
        _ = emptyEngine.process("$", shift: false)
        XCTAssertEqual(emptyBuffer.selectedRange().location, 0)
    }

    func testSingleCharBuffer() {
        let singleBuffer = VimTextBufferMock(text: "a")
        let singleEngine = VimEngine(buffer: singleBuffer)
        _ = singleEngine.process("l", shift: false) // Can't move right
        XCTAssertEqual(singleBuffer.selectedRange().location, 0)
        _ = singleEngine.process("h", shift: false) // Can't move left
        XCTAssertEqual(singleBuffer.selectedRange().location, 0)
    }

    func testSingleLineBuffer() {
        let singleLine = VimTextBufferMock(text: "hello")
        let singleEngine = VimEngine(buffer: singleLine)
        _ = singleEngine.process("j", shift: false) // No line below
        let (line, _) = singleLine.lineAndColumn(forOffset: singleLine.selectedRange().location)
        XCTAssertEqual(line, 0)
    }

    func testUnknownKeysInNormalModeAreConsumed() {
        let consumed = engine.process("z", shift: false)
        XCTAssertTrue(consumed)
    }

    func testUnknownKeysInVisualModeAreConsumed() {
        _ = engine.process("v", shift: false)
        let consumed = engine.process("z", shift: false)
        XCTAssertTrue(consumed)
    }

    func testDDOnAllLinesLeavesEmptyBuffer() {
        let twoLineBuffer = VimTextBufferMock(text: "a\nb\n")
        let twoLineEngine = VimEngine(buffer: twoLineBuffer)
        _ = twoLineEngine.process("d", shift: false)
        _ = twoLineEngine.process("d", shift: false)
        _ = twoLineEngine.process("d", shift: false)
        _ = twoLineEngine.process("d", shift: false)
        _ = twoLineEngine.process("d", shift: false)
        _ = twoLineEngine.process("d", shift: false)
        // Should not crash
    }

    func testNormalModeConsumesAllKeys() {
        // Normal mode should consume all printable keys (not pass through)
        for char: Character in ["a", "b", "z", "q", "f", "t", "n", "m"] {
            engine.reset() // Ensure engine is in Normal mode before each key
            XCTAssertTrue(engine.process(char, shift: false), "Key '\(char)' should be consumed in Normal mode")
        }
    }

    // MARK: - Operator Cancellation

    func testPendingOperatorCancelledByUnknownKey() {
        _ = engine.process("d", shift: false) // Pending delete
        _ = engine.process("z", shift: false) // Unknown → clears pending
        // Now dd should work fresh
        _ = engine.process("d", shift: false)
        _ = engine.process("d", shift: false)
        XCTAssertTrue(buffer.text.hasPrefix("second line"))
    }

    // MARK: - Visual Mode GG

    func testVisualGGExtendsToStart() {
        buffer.setSelectedRange(NSRange(location: 15, length: 0))
        _ = engine.process("v", shift: false)
        _ = engine.process("g", shift: false)
        _ = engine.process("g", shift: false)
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0)
        XCTAssertGreaterThan(sel.length, 0)
    }

    // MARK: - Mode Change Callback

    func testModeChangeCallback() {
        var modes: [VimMode] = []
        engine.onModeChange = { mode in modes.append(mode) }

        _ = engine.process("i", shift: false) // → insert
        _ = engine.process("\u{1B}", shift: false) // → normal
        _ = engine.process("v", shift: false) // → visual
        _ = engine.process("\u{1B}", shift: false) // → normal

        XCTAssertEqual(modes.count, 4)
        XCTAssertEqual(modes[0], .insert)
        XCTAssertEqual(modes[1], .normal)
        XCTAssertEqual(modes[2], .visual(linewise: false))
        XCTAssertEqual(modes[3], .normal)
    }

    func testModeChangeNotFiredWhenModeUnchanged() {
        var callCount = 0
        engine.onModeChange = { _ in callCount += 1 }

        _ = engine.process("\u{1B}", shift: false) // Already normal → no fire
        XCTAssertEqual(callCount, 0)
    }

    // MARK: - Command Callback

    func testCommandCallback() {
        _ = engine.process(":", shift: false)
        _ = engine.process("w", shift: false)
        _ = engine.process("q", shift: false)
        _ = engine.process("\r", shift: false)
        XCTAssertEqual(lastCommand, "wq")
    }

    func testCommandNotFiredOnCancel() {
        _ = engine.process(":", shift: false)
        _ = engine.process("w", shift: false)
        _ = engine.process("\u{1B}", shift: false)
        XCTAssertNil(lastCommand)
    }
}

// MARK: - VimMode Tests

@MainActor
final class VimModeTests: XCTestCase {
    func testDisplayLabels() {
        XCTAssertEqual(VimMode.normal.displayLabel, "NORMAL")
        XCTAssertEqual(VimMode.insert.displayLabel, "INSERT")
        XCTAssertEqual(VimMode.visual(linewise: false).displayLabel, "VISUAL")
        XCTAssertEqual(VimMode.visual(linewise: true).displayLabel, "VISUAL LINE")
        XCTAssertEqual(VimMode.commandLine(buffer: ":w").displayLabel, "COMMAND")
    }

    func testIsInsert() {
        XCTAssertTrue(VimMode.insert.isInsert)
        XCTAssertFalse(VimMode.normal.isInsert)
        XCTAssertFalse(VimMode.visual(linewise: false).isInsert)
        XCTAssertFalse(VimMode.commandLine(buffer: ":").isInsert)
    }

    func testIsVisual() {
        XCTAssertTrue(VimMode.visual(linewise: false).isVisual)
        XCTAssertTrue(VimMode.visual(linewise: true).isVisual)
        XCTAssertFalse(VimMode.normal.isVisual)
        XCTAssertFalse(VimMode.insert.isVisual)
        XCTAssertFalse(VimMode.commandLine(buffer: ":").isVisual)
    }

    func testEquality() {
        XCTAssertEqual(VimMode.normal, VimMode.normal)
        XCTAssertEqual(VimMode.insert, VimMode.insert)
        XCTAssertEqual(VimMode.visual(linewise: false), VimMode.visual(linewise: false))
        XCTAssertEqual(VimMode.visual(linewise: true), VimMode.visual(linewise: true))
        XCTAssertNotEqual(VimMode.visual(linewise: false), VimMode.visual(linewise: true))
        XCTAssertNotEqual(VimMode.normal, VimMode.insert)
        XCTAssertEqual(
            VimMode.commandLine(buffer: ":w"),
            VimMode.commandLine(buffer: ":w")
        )
        XCTAssertNotEqual(
            VimMode.commandLine(buffer: ":w"),
            VimMode.commandLine(buffer: ":q")
        )
    }
}

// MARK: - VimRegister Tests

@MainActor
final class VimRegisterTests: XCTestCase {
    func testDefaultValues() {
        let reg = VimRegister()
        XCTAssertEqual(reg.text, "")
        XCTAssertFalse(reg.isLinewise)
    }

    func testStoresText() {
        var reg = VimRegister()
        reg.text = "hello"
        reg.isLinewise = true
        XCTAssertEqual(reg.text, "hello")
        XCTAssertTrue(reg.isLinewise)
    }
}

// MARK: - VimCommandLineHandler Tests

@MainActor
final class VimCommandLineHandlerTests: XCTestCase {
    func testWCommandCallsExecuteQuery() {
        var handler = VimCommandLineHandler()
        var called = false
        handler.onExecuteQuery = { called = true }
        handler.handle("w")
        XCTAssertTrue(called)
    }

    func testWQCommandCallsExecuteQuery() {
        var handler = VimCommandLineHandler()
        var called = false
        handler.onExecuteQuery = { called = true }
        handler.handle("wq")
        XCTAssertTrue(called)
    }

    func testQCommandDoesNotCallExecuteQuery() {
        var handler = VimCommandLineHandler()
        var called = false
        handler.onExecuteQuery = { called = true }
        handler.handle("q")
        XCTAssertFalse(called)
    }

    func testUnknownCommandDoesNothing() {
        var handler = VimCommandLineHandler()
        var called = false
        handler.onExecuteQuery = { called = true }
        handler.handle("unknown")
        XCTAssertFalse(called)
    }

    func testTrimsWhitespace() {
        var handler = VimCommandLineHandler()
        var called = false
        handler.onExecuteQuery = { called = true }
        handler.handle("  w  ")
        XCTAssertTrue(called)
    }
}

// MARK: - VimTextBufferMock Tests

@MainActor
final class VimTextBufferMockTests: XCTestCase {
    func testLength() {
        let buf = VimTextBufferMock(text: "hello")
        XCTAssertEqual(buf.length, 5)
    }

    func testEmptyLength() {
        let buf = VimTextBufferMock(text: "")
        XCTAssertEqual(buf.length, 0)
    }

    func testLineCount() {
        let buf = VimTextBufferMock(text: "a\nb\nc\n")
        XCTAssertEqual(buf.lineCount, 3)
    }

    func testLineCountSingleLine() {
        let buf = VimTextBufferMock(text: "hello")
        XCTAssertEqual(buf.lineCount, 1)
    }

    func testLineCountEmpty() {
        let buf = VimTextBufferMock(text: "")
        XCTAssertEqual(buf.lineCount, 1)
    }

    func testLineRange() {
        let buf = VimTextBufferMock(text: "hello\nworld\n")
        let range = buf.lineRange(forOffset: 0)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 6) // "hello\n"
    }

    func testLineRangeSecondLine() {
        let buf = VimTextBufferMock(text: "hello\nworld\n")
        let range = buf.lineRange(forOffset: 6)
        XCTAssertEqual(range.location, 6)
        XCTAssertEqual(range.length, 6) // "world\n"
    }

    func testLineAndColumn() {
        let buf = VimTextBufferMock(text: "hello\nworld\n")
        let (line, col) = buf.lineAndColumn(forOffset: 8) // 'r' in "world"
        XCTAssertEqual(line, 1)
        XCTAssertEqual(col, 2)
    }

    func testOffsetForLineAndColumn() {
        let buf = VimTextBufferMock(text: "hello\nworld\n")
        let offset = buf.offset(forLine: 1, column: 2)
        XCTAssertEqual(offset, 8) // 'r' in "world"
    }

    func testCharacterAt() {
        let buf = VimTextBufferMock(text: "hello")
        XCTAssertEqual(buf.character(at: 0), 0x68) // 'h'
        XCTAssertEqual(buf.character(at: 4), 0x6F) // 'o'
    }

    func testCharacterAtOutOfBounds() {
        let buf = VimTextBufferMock(text: "hi")
        XCTAssertEqual(buf.character(at: -1), 0)
        XCTAssertEqual(buf.character(at: 5), 0)
    }

    func testSetSelectedRange() {
        let buf = VimTextBufferMock(text: "hello")
        buf.setSelectedRange(NSRange(location: 3, length: 0))
        XCTAssertEqual(buf.selectedRange().location, 3)
    }

    func testSetSelectedRangeClamped() {
        let buf = VimTextBufferMock(text: "hi")
        buf.setSelectedRange(NSRange(location: 100, length: 50))
        XCTAssertLessThanOrEqual(buf.selectedRange().location, buf.length)
    }

    func testReplaceCharacters() {
        let buf = VimTextBufferMock(text: "hello")
        buf.replaceCharacters(in: NSRange(location: 0, length: 5), with: "world")
        XCTAssertEqual(buf.text, "world")
    }

    func testReplaceCharactersInsert() {
        let buf = VimTextBufferMock(text: "hllo")
        buf.replaceCharacters(in: NSRange(location: 1, length: 0), with: "e")
        XCTAssertEqual(buf.text, "hello")
    }

    func testWordBoundaryForward() {
        let buf = VimTextBufferMock(text: "hello world")
        let pos = buf.wordBoundary(forward: true, from: 0)
        XCTAssertEqual(pos, 6) // Start of "world"
    }

    func testWordBoundaryBackward() {
        let buf = VimTextBufferMock(text: "hello world")
        let pos = buf.wordBoundary(forward: false, from: 6)
        XCTAssertEqual(pos, 0) // Start of "hello"
    }

    func testWordEnd() {
        let buf = VimTextBufferMock(text: "hello world")
        let pos = buf.wordEnd(from: 0)
        XCTAssertEqual(pos, 4) // End of "hello"
    }

    func testLineRangeClampedOffset() {
        let buf = VimTextBufferMock(text: "hi")
        // Should not crash with out-of-range offset
        let range = buf.lineRange(forOffset: 100)
        XCTAssertEqual(range.location, 0)
    }

    func testUndoRedoNoOp() {
        let buf = VimTextBufferMock(text: "hello")
        // Should not crash
        buf.undo()
        buf.redo()
        XCTAssertEqual(buf.text, "hello")
    }
}

// swiftlint:enable file_length type_body_length
