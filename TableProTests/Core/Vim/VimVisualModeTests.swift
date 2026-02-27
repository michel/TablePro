//
//  VimVisualModeTests.swift
//  TableProTests
//
//  Comprehensive visual mode tests — defines correct Vim selection behavior
//

import XCTest
@testable import TablePro

// swiftlint:disable file_length type_body_length

// MARK: - Helpers

/// Shorthand to avoid repeating `shift: false` everywhere
@MainActor
private extension VimEngine {
    @discardableResult
    func key(_ char: Character, shift: Bool = false) -> Bool {
        process(char, shift: shift)
    }

    /// Send a sequence of non-shifted keys
    func keys(_ chars: String) {
        for c in chars { key(c) }
    }
}

// MARK: - Visual Characterwise Tests

@MainActor
final class VimVisualModeTests: XCTestCase {
    // Buffer: "hello world\nsecond line\nthird line\n"
    //          0123456789012345678901234567890123 4
    //          h         1111111111222222222233333 3
    private var buffer: VimTextBufferMock!
    private var engine: VimEngine!

    override func setUp() {
        super.setUp()
        buffer = VimTextBufferMock(text: "hello world\nsecond line\nthird line\n")
        engine = VimEngine(buffer: buffer)
    }

    // MARK: - Entry: v (characterwise)

    func testVEntersVisualCharacterwise() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        XCTAssertEqual(engine.mode, .visual(linewise: false))
    }

    func testVInitialSelectionIncludesCursorCharacter() {
        // In Vim, pressing v at position 0 visually selects the character under
        // the cursor. The buffer selection should be (0, 1) = "h".
        buffer.setSelectedRange(NSRange(location: 3, length: 0))
        engine.key("v")
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 3, "Selection should start at cursor position")
        XCTAssertEqual(sel.length, 1, "v should select the character under the cursor")
    }

    // MARK: - Entry: V (linewise)

    func testShiftVEntersVisualLinewise() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        engine.key("V", shift: true)
        XCTAssertEqual(engine.mode, .visual(linewise: true))
    }

    func testShiftVSelectsEntireLine() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        engine.key("V", shift: true)
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0)
        XCTAssertEqual(sel.length, 12) // "hello world\n"
    }

    // MARK: - Forward Motions (characterwise)

    func testVLSelectsTwoCharacters() {
        // v at pos 0 selects "h", then l extends to include "e" → "he"
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("l")
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0)
        XCTAssertEqual(sel.length, 2, "vl should select 2 chars: 'he'")
        XCTAssertEqual(buffer.string(in: sel), "he")
    }

    func testVLLSelectsThreeCharacters() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("l")
        engine.key("l")
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0)
        XCTAssertEqual(sel.length, 3, "vll should select 3 chars: 'hel'")
        XCTAssertEqual(buffer.string(in: sel), "hel")
    }

    func testVWExtendsToNextWord() {
        // From pos 0: w goes to pos 6 ("world"), inclusive selection = (0, 7)
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("w")
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0)
        XCTAssertEqual(buffer.string(in: sel), "hello w")
    }

    func testVEExtendsToWordEnd() {
        // From pos 0: e goes to pos 4 (end of "hello"), inclusive = (0, 5)
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("e")
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0)
        XCTAssertEqual(sel.length, 5, "ve should select 'hello'")
        XCTAssertEqual(buffer.string(in: sel), "hello")
    }

    func testVDollarExtendsToLineEnd() {
        // From pos 0: $ goes to last char of line (pos 10 = 'd'), inclusive selection
        // includes that character → "hello world" (11 chars). In Vim, v$ also includes
        // the newline, but the $ motion positions at last content char.
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("$")
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0)
        // Selection should include at least "hello world" (the last content char 'd')
        XCTAssertGreaterThanOrEqual(sel.length, 11)
    }

    func testVJExtendsToNextLine() {
        // From pos 0: j goes to line 1 col 0 = pos 12, inclusive = (0, 13)
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("j")
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0)
        XCTAssertGreaterThanOrEqual(sel.length, 13, "vj should extend into the second line")
    }

    func testVGExtendsToBufferEnd() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("G", shift: true)
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0)
        XCTAssertEqual(sel.location + sel.length, buffer.length, "vG should extend to buffer end")
    }

    // MARK: - Backward Motions (characterwise)

    func testVHSelectsBackward() {
        // At pos 5, v selects " " (pos 5), h moves cursor to 4 → selects "o " (pos 4-5)
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        engine.key("v")
        engine.key("h")
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 4)
        XCTAssertEqual(sel.length, 2, "vh backward should select 2 chars")
        XCTAssertEqual(buffer.string(in: sel), "o ")
    }

    func testVBSelectsBackwardToWordStart() {
        // At pos 6 (start of "world"), v selects "w", b → pos 0, inclusive = (0, 7)
        buffer.setSelectedRange(NSRange(location: 6, length: 0))
        engine.key("v")
        engine.key("b")
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0)
        XCTAssertEqual(buffer.string(in: sel), "hello w")
    }

    func testVKSelectsUpward() {
        // At pos 15 (in "second line"), v then k → extends to line 0
        buffer.setSelectedRange(NSRange(location: 15, length: 0))
        engine.key("v")
        engine.key("k")
        let sel = buffer.selectedRange()
        XCTAssertLessThan(sel.location, 12, "vk should extend into the first line")
        XCTAssertGreaterThan(sel.length, 0)
    }

    func testV0SelectsToLineStart() {
        // At pos 5, v selects " ", 0 → pos 0, inclusive = (0, 6)
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        engine.key("v")
        engine.key("0")
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0)
        XCTAssertEqual(buffer.string(in: sel), "hello ")
    }

    // MARK: - Forward then Backward (cursor crosses anchor)

    func testVLThenHReturnsToSingleChar() {
        // At pos 3: v selects "l" (3,1), l extends to "lo" (3,2), h returns to "l" (3,1)
        buffer.setSelectedRange(NSRange(location: 3, length: 0))
        engine.key("v")
        engine.key("l")
        engine.key("h")
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 3)
        XCTAssertEqual(sel.length, 1, "vl then h should return to single char selection")
    }

    func testVHThenLReturnsToSingleChar() {
        // At pos 3: v selects "l" (3,1), h to "ll" (2,2), l returns to "l" (3,1)
        buffer.setSelectedRange(NSRange(location: 3, length: 0))
        engine.key("v")
        engine.key("h")
        engine.key("l")
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 3)
        XCTAssertEqual(sel.length, 1, "vh then l should return to single char selection")
    }

    // MARK: - gg in Visual Mode

    func testVggExtendsToBufferStart() {
        buffer.setSelectedRange(NSRange(location: 15, length: 0))
        engine.key("v")
        engine.key("g")
        engine.key("g")
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0, "vgg should extend selection to start of buffer")
        XCTAssertGreaterThan(sel.length, 0)
    }

    func testVgUnknownConsumed() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        let consumed = engine.key("g")
        XCTAssertTrue(consumed)
        let consumed2 = engine.key("z") // Unknown after g
        XCTAssertTrue(consumed2)
        XCTAssertEqual(engine.mode, .visual(linewise: false), "Should still be in visual mode")
    }

    // MARK: - Delete (d/x) in Visual Characterwise

    func testVLDDeletesExactSelection() {
        // At pos 0: v selects "h", l → "he", d deletes "he"
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("l")
        engine.key("d")
        XCTAssertEqual(engine.mode, .normal)
        XCTAssertTrue(buffer.text.hasPrefix("llo world"), "Should delete exactly 'he'")
    }

    func testVXDeletesSameAsD() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("l")
        engine.key("x")
        XCTAssertEqual(engine.mode, .normal)
        XCTAssertTrue(buffer.text.hasPrefix("llo world"))
    }

    func testVisualDeleteSetsRegister() {
        // Delete "he", register should contain "he" (not linewise)
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("l")
        engine.key("d")
        // Paste to verify register content
        engine.key("P", shift: true) // Paste before cursor
        XCTAssertTrue(buffer.text.hasPrefix("hello"), "Register should contain 'he' and paste restores it")
    }

    func testVisualDeleteEmptySelectionStillExitsToNormal() {
        // If somehow the selection is empty, d should still return to normal
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        // Force selection to empty
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("d")
        XCTAssertEqual(engine.mode, .normal)
    }

    // MARK: - Yank (y) in Visual Characterwise

    func testVYankPreservesText() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("l")
        engine.key("y")
        XCTAssertEqual(engine.mode, .normal)
        XCTAssertTrue(buffer.text.hasPrefix("hello world"), "Yank should not modify text")
    }

    func testVYankCollapsesSelectionToStart() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("l")
        engine.key("l")
        engine.key("y")
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.length, 0, "After yank, selection should be collapsed")
        XCTAssertEqual(sel.location, 0, "Cursor should be at start of yanked region")
    }

    func testVYankThenPasteRestoresContent() {
        // Yank "hello" then paste after cursor
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("e") // Extend to end of "hello"
        engine.key("y")
        engine.key("p") // Paste after
        XCTAssertTrue(buffer.text.contains("hhello"), "Yanked 'hello' pasted after 'h'")
    }

    // MARK: - Change (c) in Visual Characterwise

    func testVCDeletesSelectionAndEntersInsert() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("l")
        engine.key("c")
        XCTAssertEqual(engine.mode, .insert)
        XCTAssertTrue(buffer.text.hasPrefix("llo world"), "Change should delete 'he'")
    }

    // MARK: - Escape from Visual

    func testEscapeExitsVisualToNormal() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("l")
        engine.key("\u{1B}") // Escape
        XCTAssertEqual(engine.mode, .normal)
        XCTAssertEqual(buffer.selectedRange().length, 0, "Escape should collapse selection")
    }

    // MARK: - Mode Switching: v ↔ V

    func testVThenVExitsVisualMode() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("v") // Toggle off
        XCTAssertEqual(engine.mode, .normal)
        XCTAssertEqual(buffer.selectedRange().length, 0, "Second v should exit visual and collapse selection")
    }

    func testVThenShiftVSwitchesToLinewise() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        engine.key("v")
        engine.key("V", shift: true)
        XCTAssertEqual(engine.mode, .visual(linewise: true))
        let sel = buffer.selectedRange()
        // In linewise mode, entire line should be selected
        XCTAssertEqual(sel.location, 0, "Linewise should start at line beginning")
        XCTAssertEqual(sel.length, 12, "Linewise should select entire line: 'hello world\\n'")
    }

    func testShiftVThenVSwitchesToCharacterwise() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        engine.key("V", shift: true) // Enter visual line
        engine.key("v") // Switch to characterwise
        XCTAssertEqual(engine.mode, .visual(linewise: false))
    }

    func testShiftVThenShiftVExitsVisualMode() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("V", shift: true)
        engine.key("V", shift: true)
        XCTAssertEqual(engine.mode, .normal)
        XCTAssertEqual(buffer.selectedRange().length, 0)
    }

    // MARK: - Visual Line Mode: Motions

    func testVisualLineJExtendsToNextLine() {
        buffer.setSelectedRange(NSRange(location: 5, length: 0))
        engine.key("V", shift: true) // Select line 0
        engine.key("j") // Extend to line 1
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0, "Should start at beginning of line 0")
        XCTAssertEqual(sel.length, 24, "Should select lines 0+1: 'hello world\\nsecond line\\n'")
    }

    func testVisualLineKExtendsUpward() {
        buffer.setSelectedRange(NSRange(location: 15, length: 0))
        engine.key("V", shift: true) // Select line 1
        engine.key("k") // Extend up to line 0
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0, "Should start at beginning of line 0")
        XCTAssertEqual(sel.length, 24, "Should select lines 0+1")
    }

    func testVisualLineDDeletesFullLines() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("V", shift: true)
        engine.key("j") // Select lines 0 and 1
        engine.key("d")
        XCTAssertEqual(engine.mode, .normal)
        XCTAssertTrue(buffer.text.hasPrefix("third line"), "Should delete first two lines")
    }

    func testVisualLineYankIsLinewise() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("V", shift: true)
        engine.key("y")
        // Verify it's linewise by pasting below
        engine.key("p")
        // Should paste "hello world\n" as a new line below
        XCTAssertTrue(buffer.text.hasPrefix("hello world\nhello world\n"))
    }

    // MARK: - Unknown Keys

    func testUnknownKeyConsumedInVisualMode() {
        engine.key("v")
        let consumed = engine.key("z")
        XCTAssertTrue(consumed, "Unknown keys should be consumed in visual mode")
        XCTAssertEqual(engine.mode, .visual(linewise: false), "Should remain in visual mode")
    }

    // MARK: - Edge Cases

    func testVisualModeAtEndOfLine() {
        // Cursor at last char of line 0 (pos 10 = 'd')
        buffer.setSelectedRange(NSRange(location: 10, length: 0))
        engine.key("v")
        engine.key("l") // Should not go past newline
        let sel = buffer.selectedRange()
        // In Vim, l at end of line stays put in visual mode or extends to newline
        XCTAssertLessThanOrEqual(sel.location + sel.length, 12)
    }

    func testVisualModeAtBufferStart() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("v")
        engine.key("h") // Can't go left from pos 0
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0)
        XCTAssertEqual(sel.length, 1, "h at buffer start should keep single-char selection")
    }

    func testVisualModeOnSingleCharBuffer() {
        let buf = VimTextBufferMock(text: "a")
        let eng = VimEngine(buffer: buf)
        eng.key("v")
        let sel = buf.selectedRange()
        XCTAssertEqual(sel.location, 0)
        XCTAssertEqual(sel.length, 1)
        eng.key("d")
        XCTAssertEqual(buf.text, "")
        XCTAssertEqual(eng.mode, .normal)
    }

    func testVisualModeOnEmptyBuffer() {
        let buf = VimTextBufferMock(text: "")
        let eng = VimEngine(buffer: buf)
        eng.key("v")
        // Should enter visual but selection may be (0, 0)
        XCTAssertEqual(eng.mode, .visual(linewise: false))
        eng.key("d")
        XCTAssertEqual(eng.mode, .normal)
        XCTAssertEqual(buf.text, "")
    }

    func testVisualLineModeGGExtendsToFirstLine() {
        buffer.setSelectedRange(NSRange(location: 28, length: 0)) // "third line"
        engine.key("V", shift: true) // Select line 2
        engine.key("g")
        engine.key("g") // gg → extend to line 0
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0, "gg in visual line should extend to first line")
        XCTAssertEqual(sel.length, buffer.length, "Should select all lines from 0 to 2")
    }

    func testVisualCharGGExtendsToStart() {
        buffer.setSelectedRange(NSRange(location: 15, length: 0))
        engine.key("v")
        engine.key("g")
        engine.key("g")
        let sel = buffer.selectedRange()
        XCTAssertEqual(sel.location, 0)
        XCTAssertGreaterThanOrEqual(sel.length, 16, "vgg should select from pos 0 to anchor 15 inclusive")
    }

    func testVisualLineModeChangeDeletesAndInsertsMode() {
        buffer.setSelectedRange(NSRange(location: 0, length: 0))
        engine.key("V", shift: true)
        engine.key("c")
        XCTAssertEqual(engine.mode, .insert)
    }
}

// swiftlint:enable file_length type_body_length
