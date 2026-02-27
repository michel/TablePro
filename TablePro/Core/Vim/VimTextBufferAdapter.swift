//
//  VimTextBufferAdapter.swift
//  TablePro
//
//  Adapts CodeEditTextView's TextView to the VimTextBuffer protocol
//

import AppKit
import CodeEditTextView
import Foundation

/// Bridges CodeEditTextView's TextView to VimTextBuffer for the Vim engine
@MainActor
final class VimTextBufferAdapter: VimTextBuffer {
    private weak var textView: TextView?

    init(textView: TextView) {
        self.textView = textView
    }

    // MARK: - VimTextBuffer

    var length: Int {
        guard let textView else { return 0 }
        return (textView.string as NSString).length
    }

    var lineCount: Int {
        guard let textView else { return 0 }
        let nsString = textView.string as NSString
        if nsString.length == 0 { return 1 }
        var count = 0
        var index = 0
        while index < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            count += 1
            index = lineRange.location + lineRange.length
        }
        return max(1, count)
    }

    func lineRange(forOffset offset: Int) -> NSRange {
        guard let textView else { return NSRange(location: 0, length: 0) }
        let nsString = textView.string as NSString
        let clampedOffset = min(max(0, offset), nsString.length)
        return nsString.lineRange(for: NSRange(location: clampedOffset, length: 0))
    }

    func lineAndColumn(forOffset offset: Int) -> (line: Int, column: Int) {
        guard let textView else { return (0, 0) }
        let nsString = textView.string as NSString
        let clampedOffset = min(max(0, offset), nsString.length)
        var line = 0
        var index = 0
        while index < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            if clampedOffset >= lineRange.location && clampedOffset < lineRange.location + lineRange.length {
                return (line, clampedOffset - lineRange.location)
            }
            line += 1
            index = lineRange.location + lineRange.length
        }
        // At end of text
        return (max(0, line), clampedOffset - index + (nsString.length > 0 ? 0 : 0))
    }

    func offset(forLine line: Int, column: Int) -> Int {
        guard let textView else { return 0 }
        let nsString = textView.string as NSString
        var currentLine = 0
        var index = 0
        while index < nsString.length && currentLine < line {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            currentLine += 1
            index = lineRange.location + lineRange.length
        }
        // Now index is at the start of the target line
        let lineRange = nsString.lineRange(for: NSRange(location: min(index, nsString.length), length: 0))
        // Content length excludes trailing newline
        let contentLength: Int
        let lineEnd = lineRange.location + lineRange.length
        if lineEnd > lineRange.location && lineEnd <= nsString.length
            && nsString.character(at: lineEnd - 1) == 0x0A {
            contentLength = lineRange.length - 1
        } else {
            contentLength = lineRange.length
        }
        let clampedCol = min(column, max(0, contentLength - 1))
        return lineRange.location + max(0, clampedCol)
    }

    func character(at offset: Int) -> unichar {
        guard let textView else { return 0 }
        let nsString = textView.string as NSString
        guard offset >= 0 && offset < nsString.length else { return 0 }
        return nsString.character(at: offset)
    }

    func wordBoundary(forward: Bool, from offset: Int) -> Int {
        guard let textView else { return offset }
        let nsString = textView.string as NSString
        guard nsString.length > 0 else { return 0 }

        if forward {
            var pos = min(offset, nsString.length - 1)
            // Skip current word characters
            while pos < nsString.length && isWordChar(nsString.character(at: pos)) {
                pos += 1
            }
            // Skip whitespace/non-word characters
            while pos < nsString.length && !isWordChar(nsString.character(at: pos)) {
                pos += 1
            }
            return min(pos, nsString.length)
        } else {
            var pos = min(offset, nsString.length)
            if pos > 0 { pos -= 1 }
            // Skip whitespace/non-word characters backward
            while pos > 0 && !isWordChar(nsString.character(at: pos)) {
                pos -= 1
            }
            // Skip word characters backward
            while pos > 0 && isWordChar(nsString.character(at: pos - 1)) {
                pos -= 1
            }
            return max(0, pos)
        }
    }

    func wordEnd(from offset: Int) -> Int {
        guard let textView else { return offset }
        let nsString = textView.string as NSString
        guard nsString.length > 0 else { return 0 }

        var pos = min(offset + 1, nsString.length - 1)
        // Skip whitespace
        while pos < nsString.length && !isWordChar(nsString.character(at: pos)) {
            pos += 1
        }
        // Go to end of word
        while pos < nsString.length - 1 && isWordChar(nsString.character(at: pos + 1)) {
            pos += 1
        }
        return min(pos, nsString.length - 1)
    }

    func selectedRange() -> NSRange {
        guard let textView else { return NSRange(location: 0, length: 0) }
        return textView.selectedRange()
    }

    func string(in range: NSRange) -> String {
        guard let textView else { return "" }
        let nsString = textView.string as NSString
        let clampedRange = NSRange(
            location: max(0, range.location),
            length: min(range.length, nsString.length - max(0, range.location))
        )
        guard clampedRange.length > 0 else { return "" }
        return nsString.substring(with: clampedRange)
    }

    func setSelectedRange(_ range: NSRange) {
        guard let textView else { return }
        let clampedLocation = max(0, min(range.location, (textView.string as NSString).length))
        let maxLength = (textView.string as NSString).length - clampedLocation
        let clampedLength = max(0, min(range.length, maxLength))
        let clampedRange = NSRange(location: clampedLocation, length: clampedLength)
        textView.selectionManager.setSelectedRange(clampedRange)
        // CodeEditTextView's setSelectedRange (singular) doesn't call setNeedsDisplay,
        // so selection highlights (drawn in draw(_:)) won't render without this.
        if clampedRange.length > 0 {
            textView.needsDisplay = true
        }
        textView.scrollToRange(clampedRange)
    }

    func replaceCharacters(in range: NSRange, with string: String) {
        guard let textView else { return }
        textView.replaceCharacters(in: range, with: string)
    }

    func undo() {
        guard let textView else { return }
        textView.undoManager?.undo()
    }

    func redo() {
        guard let textView else { return }
        textView.undoManager?.redo()
    }

    // MARK: - Helpers

    private func isWordChar(_ char: unichar) -> Bool {
        // Word characters: alphanumeric + underscore (Vim's 'iskeyword' default)
        guard let scalar = UnicodeScalar(char) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || char == 0x5F // underscore
    }
}
