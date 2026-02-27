//
//  VimRegister.swift
//  TablePro
//
//  Vim register for storing yanked/deleted text
//

/// Vim register for yank/delete/paste operations
struct VimRegister {
    /// The stored text content
    var text: String = ""

    /// Whether the text was yanked/deleted linewise (entire lines)
    var isLinewise: Bool = false
}
