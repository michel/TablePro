//
//  EditableFieldView.swift
//  TablePro
//
//  Compact, type-aware field editor for right sidebar.
//  Two-line layout: field name + type badge, then editor + menu.
//

import AppKit
import SwiftUI

/// Compact editable field view with type-aware editors
struct EditableFieldView: View {
    let columnName: String
    let columnType: String
    let columnTypeEnum: ColumnType
    let isLongText: Bool
    @Binding var value: String
    let originalValue: String?
    let hasMultipleValues: Bool
    let isPendingNull: Bool
    let isPendingDefault: Bool
    let isModified: Bool

    let onSetNull: () -> Void
    let onSetDefault: () -> Void
    let onSetEmpty: () -> Void
    let onSetFunction: (String) -> Void
    let onUpdateValue: (String) -> Void

    @FocusState private var isFocused: Bool

    private var placeholderText: String {
        if hasMultipleValues {
            return String(localized: "Multiple values")
        } else if let original = originalValue {
            return original
        } else {
            return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Line 1: modified indicator + field name + type badge
            HStack(spacing: 4) {
                if isModified {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }

                Text(columnName)
                    .font(.system(size: DesignConstants.FontSize.small, weight: .medium))
                    .lineLimit(1)

                Spacer()

                Text(columnTypeEnum.badgeLabel)
                    .font(.system(size: DesignConstants.FontSize.tiny))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color(NSColor.quaternaryLabelColor).opacity(0.3))
                    .clipShape(Capsule())
            }

            // Line 2: type-aware editor + menu button
            HStack(spacing: 4) {
                typeAwareEditor

                fieldMenu
            }
        }
    }

    // MARK: - Type-Aware Editor

    @ViewBuilder
    private var typeAwareEditor: some View {
        if isPendingNull {
            specialValueLabel("NULL")
        } else if isPendingDefault {
            specialValueLabel("DEFAULT")
        } else if columnTypeEnum.isBooleanType {
            booleanPicker
        } else if columnTypeEnum.isEnumType, let values = columnTypeEnum.enumValues, !values.isEmpty {
            enumPicker(values: values)
        } else if isLongText || columnTypeEnum.isJsonType {
            multiLineEditor
        } else {
            singleLineEditor
        }
    }

    private func specialValueLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: DesignConstants.FontSize.small))
            .foregroundStyle(.secondary)
            .italic()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var booleanPicker: some View {
        Picker("", selection: Binding(
            get: { normalizeBooleanValue(value) },
            set: { onUpdateValue($0) }
        )) {
            Text("true").tag("1")
            Text("false").tag("0")
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func enumPicker(values: [String]) -> some View {
        Picker("", selection: Binding(
            get: { value },
            set: { onUpdateValue($0) }
        )) {
            ForEach(values, id: \.self) { val in
                Text(val).tag(val)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var multiLineEditor: some View {
        TextEditor(text: $value)
            .font(.system(size: DesignConstants.FontSize.small, design: .monospaced))
            .focused($isFocused)
            .frame(height: 80)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(NSColor.separatorColor).opacity(0.5))
            )
    }

    private var singleLineEditor: some View {
        TextField(placeholderText, text: $value)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: DesignConstants.FontSize.small))
            .focused($isFocused)
    }

    // MARK: - Field Menu

    private var fieldMenu: some View {
        Menu {
            Button("Set NULL") {
                onSetNull()
            }

            Button("Set DEFAULT") {
                onSetDefault()
            }

            Button("Set EMPTY") {
                onSetEmpty()
            }

            Divider()

            if columnTypeEnum.isJsonType {
                Button("Pretty Print") {
                    if let formatted = prettyPrintJson(value) {
                        onUpdateValue(formatted)
                    }
                }
            }

            Button("Copy Value") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }

            Divider()

            Menu("SQL Functions") {
                Button("NOW()") { onSetFunction("NOW()") }
                Button("CURRENT_TIMESTAMP()") { onSetFunction("CURRENT_TIMESTAMP()") }
                Button("CURDATE()") { onSetFunction("CURDATE()") }
                Button("CURTIME()") { onSetFunction("CURTIME()") }
                Button("UTC_TIMESTAMP()") { onSetFunction("UTC_TIMESTAMP()") }
            }

            if isPendingNull || isPendingDefault {
                Divider()
                Button("Clear") {
                    onUpdateValue(originalValue ?? "")
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Helpers

    private func normalizeBooleanValue(_ val: String) -> String {
        let lower = val.lowercased()
        if lower == "true" || lower == "1" || lower == "t" || lower == "yes" {
            return "1"
        }
        return "0"
    }

    private func prettyPrintJson(_ jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(
                  withJSONObject: jsonObject,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return prettyString
    }
}

/// Read-only field view with compact layout
struct ReadOnlyFieldView: View {
    let columnName: String
    let columnType: String
    let columnTypeEnum: ColumnType
    let isLongText: Bool
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Line 1: field name + type badge
            HStack(spacing: 4) {
                Text(columnName)
                    .font(.system(size: DesignConstants.FontSize.small, weight: .medium))
                    .lineLimit(1)

                Spacer()

                Text(columnTypeEnum.badgeLabel)
                    .font(.system(size: DesignConstants.FontSize.tiny))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color(NSColor.quaternaryLabelColor).opacity(0.3))
                    .clipShape(Capsule())
            }

            // Line 2: value display
            Group {
                if let value {
                    if isLongText || columnTypeEnum.isJsonType {
                        Text(value)
                            .font(.system(size: DesignConstants.FontSize.small, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, maxHeight: 80, alignment: .topLeading)
                            .clipped()
                    } else {
                        Text(value)
                            .font(.system(size: DesignConstants.FontSize.small))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("NULL")
                        .font(.system(size: DesignConstants.FontSize.small))
                        .foregroundStyle(.tertiary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contextMenu {
                if let value {
                    Button("Copy Value") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                    }
                }
            }
        }
    }
}
