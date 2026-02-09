//
//  TableProEditorTheme.swift
//  TablePro
//
//  Adapts SQLEditorTheme colors to CodeEditSourceEditor's EditorTheme.
//

import AppKit
import CodeEditSourceEditor

/// Maps TablePro's SQLEditorTheme colors to CodeEditSourceEditor's EditorTheme
struct TableProEditorTheme {
    /// Build an EditorTheme from the current SQLEditorTheme settings
    static func make() -> EditorTheme {
        let textAttr = EditorTheme.Attribute(color: rgb(SQLEditorTheme.text))
        let commentAttr = EditorTheme.Attribute(color: rgb(SQLEditorTheme.comment))
        let keywordAttr = EditorTheme.Attribute(color: rgb(SQLEditorTheme.keyword), bold: true)
        let stringAttr = EditorTheme.Attribute(color: rgb(SQLEditorTheme.string))
        let numberAttr = EditorTheme.Attribute(color: rgb(SQLEditorTheme.number))
        let variableAttr = EditorTheme.Attribute(color: rgb(SQLEditorTheme.null))

        return EditorTheme(
            text: textAttr,
            insertionPoint: rgb(SQLEditorTheme.insertionPoint),
            invisibles: EditorTheme.Attribute(color: rgb(.tertiaryLabelColor)),
            background: rgb(SQLEditorTheme.background),
            lineHighlight: rgb(SQLEditorTheme.currentLineHighlight),
            selection: rgb(.selectedTextBackgroundColor),
            keywords: keywordAttr,
            commands: keywordAttr,
            types: EditorTheme.Attribute(color: rgb(.systemTeal)),
            attributes: variableAttr,
            variables: variableAttr,
            values: variableAttr,
            numbers: numberAttr,
            strings: stringAttr,
            characters: stringAttr,
            comments: commentAttr
        )
    }

    /// Convert any NSColor to sRGB so that `brightnessComponent` (used by MinimapView) works.
    private static func rgb(_ color: NSColor) -> NSColor {
        color.usingColorSpace(.sRGB) ?? color
    }
}
