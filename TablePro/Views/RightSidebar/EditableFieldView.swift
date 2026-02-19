//
//  EditableFieldView.swift
//  TablePro
//
//  Reusable editable field component for right sidebar.
//  Native macOS form-style field with menu button.
//

import SwiftUI

/// Editable field view with native macOS styling
struct EditableFieldView: View {
    let columnName: String
    let columnType: String
    let isLongText: Bool  // NEW: Whether to use multi-line editor
    @Binding var value: String
    let originalValue: String?
    let hasMultipleValues: Bool  // Whether multiple selected rows have different values
    let isPendingNull: Bool
    let isPendingDefault: Bool
    let isModified: Bool

    let onSetNull: () -> Void
    let onSetDefault: () -> Void
    let onSetFunction: (String) -> Void

    @FocusState private var isFocused: Bool

    private var displayValue: String {
        if isPendingNull {
            return "NULL"
        } else if isPendingDefault {
            return "DEFAULT"
        } else {
            return value
        }
    }

    private var placeholderText: String {
        if hasMultipleValues {
            return "Multiple values"
        } else if isPendingNull {
            return "NULL"
        } else if isPendingDefault {
            return "DEFAULT"
        } else if let original = originalValue {
            return original
        } else {
            return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(columnName)
                    .font(.system(size: DesignConstants.FontSize.small))
                    .foregroundStyle(.secondary)

                Text(columnType)
                    .font(.system(size: DesignConstants.FontSize.tiny))
                    .foregroundStyle(.tertiary)

                if isModified {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }

            HStack(spacing: 4) {
                if isLongText {
                    TextEditor(text: $value)
                        .font(.system(size: DesignConstants.FontSize.small, design: .monospaced))
                        .disabled(isPendingNull || isPendingDefault)
                        .focused($isFocused)
                        .frame(height: 120)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color(NSColor.separatorColor).opacity(0.5))
                        )
                } else {
                    TextField(placeholderText, text: $value)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: DesignConstants.FontSize.small))
                        .disabled(isPendingNull || isPendingDefault)
                        .focused($isFocused)
                }

                Menu {
                    Button("Set NULL") {
                        onSetNull()
                    }

                    Button("Set DEFAULT") {
                        onSetDefault()
                    }

                    Divider()

                    Menu("SQL Functions") {
                        Button("NOW()") {
                            onSetFunction("NOW()")
                        }
                        Button("CURRENT_TIMESTAMP()") {
                            onSetFunction("CURRENT_TIMESTAMP()")
                        }
                        Button("CURDATE()") {
                            onSetFunction("CURDATE()")
                        }
                        Button("CURTIME()") {
                            onSetFunction("CURTIME()")
                        }
                        Button("UTC_TIMESTAMP()") {
                            onSetFunction("UTC_TIMESTAMP()")
                        }
                    }

                    if isPendingNull || isPendingDefault {
                        Divider()
                        Button("Clear") {
                            value = originalValue ?? ""
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Set special value")
            }
        }
    }
}

/// Read-only field view (for readonly mode or deleted rows)
struct ReadOnlyFieldView: View {
    let columnName: String
    let columnType: String
    let isLongText: Bool  // NEW: Whether to use multi-line display
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(columnName)
                    .font(.system(size: DesignConstants.FontSize.small))
                    .foregroundStyle(.secondary)

                Text(columnType)
                    .font(.system(size: DesignConstants.FontSize.tiny))
                    .foregroundStyle(.tertiary)
            }

            Group {
                if isLongText {
                    if let value = value {
                        Text(value)
                            .font(.system(size: DesignConstants.FontSize.small, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, maxHeight: 120, alignment: .topLeading)
                            .clipped()
                    } else {
                        Text("NULL")
                            .font(.system(size: DesignConstants.FontSize.small))
                            .foregroundStyle(.tertiary)
                            .italic()
                            .frame(maxWidth: .infinity, maxHeight: 120, alignment: .topLeading)
                    }
                } else {
                    if let value = value {
                        Text(value)
                            .font(.system(size: DesignConstants.FontSize.small))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("NULL")
                            .font(.system(size: DesignConstants.FontSize.small))
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}
