//
//  EditableCell.swift
//  OpenTable
//
//  Editable cell component for data tables
//

import SwiftUI

/// A cell that can be edited inline
struct EditableCell: View {
    let value: String?
    let isModified: Bool
    let isDeleted: Bool
    let onEdit: (String?) -> Void
    
    @State private var isEditing = false
    @State private var editText = ""
    @State private var isHovering = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack {
            // Background
            Rectangle()
                .fill(backgroundColor)
            
            // Content
            if isEditing {
                editingView
            } else {
                displayView
            }
        }
        .frame(minWidth: 60, maxWidth: .infinity, alignment: .leading)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    // MARK: - Display View
    
    private var displayView: some View {
        HStack(spacing: 4) {
            if let value = value {
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(isDeleted ? .secondary : .primary)
                    .strikethrough(isDeleted)
                    .lineLimit(1)
            } else {
                Text("NULL")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .italic()
            }
            
            Spacer()
            
            if isHovering && !isDeleted {
                Button(action: startEditing) {
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !isDeleted {
                startEditing()
            }
        }
    }
    
    // MARK: - Editing View
    
    private var editingView: some View {
        HStack(spacing: 4) {
            TextField("", text: $editText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focused($isFocused)
                .onSubmit {
                    commitEdit()
                }
                .onExitCommand {
                    cancelEdit()
                }
            
            Button(action: setNull) {
                Text("NULL")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.borderless)
            .help("Set to NULL")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
    
    // MARK: - Background
    
    private var backgroundColor: Color {
        if isDeleted {
            return Color.red.opacity(0.1)
        } else if isModified {
            return Color.yellow.opacity(0.15)
        } else if isEditing {
            return Color(nsColor: .controlBackgroundColor)
        } else if isHovering {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.1)
        }
        return Color.clear
    }
    
    // MARK: - Actions
    
    private func startEditing() {
        editText = value ?? ""
        isEditing = true
        isFocused = true
    }
    
    private func commitEdit() {
        let newValue = editText.isEmpty ? nil : editText
        if newValue != value {
            onEdit(newValue)
        }
        isEditing = false
    }
    
    private func cancelEdit() {
        isEditing = false
    }
    
    private func setNull() {
        onEdit(nil)
        isEditing = false
    }
}

#Preview("Normal") {
    EditableCell(value: "Hello World", isModified: false, isDeleted: false) { _ in }
        .frame(width: 200, height: 30)
}

#Preview("Modified") {
    EditableCell(value: "Changed", isModified: true, isDeleted: false) { _ in }
        .frame(width: 200, height: 30)
}

#Preview("NULL") {
    EditableCell(value: nil, isModified: false, isDeleted: false) { _ in }
        .frame(width: 200, height: 30)
}

#Preview("Deleted") {
    EditableCell(value: "Deleted Row", isModified: false, isDeleted: true) { _ in }
        .frame(width: 200, height: 30)
}
