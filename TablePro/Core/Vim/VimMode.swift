//
//  VimMode.swift
//  TablePro
//
//  Vim editing modes for the SQL editor
//

/// Vim editing modes
enum VimMode: Equatable {
    case normal
    case insert
    case visual(linewise: Bool)
    case commandLine(buffer: String)

    /// Display label for the mode indicator
    var displayLabel: String {
        switch self {
        case .normal: return "NORMAL"
        case .insert: return "INSERT"
        case .visual(let linewise): return linewise ? "VISUAL LINE" : "VISUAL"
        case .commandLine: return "COMMAND"
        }
    }

    /// Whether this mode is an insert mode (text input passes through)
    var isInsert: Bool {
        if case .insert = self { return true }
        return false
    }

    /// Whether this mode is a visual selection mode
    var isVisual: Bool {
        if case .visual = self { return true }
        return false
    }
}
