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
    let originalValue: String?
    let hasMultipleValues: Bool
    let isPendingNull: Bool
    let isPendingDefault: Bool
    
    @Binding var value: String
    
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
            // Label
            HStack(spacing: 4) {
                Text(columnName)
                    .font(.system(size: DesignConstants.FontSize.small))
                    .foregroundStyle(.secondary)
                
                Text(columnType)
                    .font(.system(size: DesignConstants.FontSize.tiny))
                    .foregroundStyle(.tertiary)
            }
            
            // Input row
            HStack(spacing: 0) {
                // Text field - custom styled for full control
                TextField(placeholderText, text: $value)
                    .textFieldStyle(.plain)
                    .font(.system(size: DesignConstants.FontSize.small))
                    .disabled(isPendingNull || isPendingDefault)
                    .focused($isFocused)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
                
                // Menu button - custom button to avoid any default indicators
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
                .padding(.leading, 6)
                .help("Set special value")
            }
        }
        .padding(.vertical, 6)
    }
}

/// Read-only field view (for readonly mode or deleted rows)
struct ReadOnlyFieldView: View {
    let columnName: String
    let columnType: String
    let value: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Label
            HStack(spacing: 4) {
                Text(columnName)
                    .font(.system(size: DesignConstants.FontSize.small))
                    .foregroundStyle(.secondary)
                
                Text(columnType)
                    .font(.system(size: DesignConstants.FontSize.tiny))
                    .foregroundStyle(.tertiary)
            }
            
            // Value display - looks like disabled text field
            HStack {
                if let value = value {
                    Text(value)
                        .font(.system(size: DesignConstants.FontSize.small))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("NULL")
                        .font(.system(size: DesignConstants.FontSize.small))
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
        }
        .padding(.vertical, 6)
    }
}
