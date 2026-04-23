//
//  BooleanPickerView.swift
//  TablePro
//

import SwiftUI

internal struct BooleanPickerView: View {
    let context: FieldEditorContext

    var body: some View {
        Picker(selection: Binding(
            get: { normalizeBooleanValue(context.value.wrappedValue) },
            set: { context.value.wrappedValue = $0 }
        )) {
            Text("true").tag("1")
            Text("false").tag("0")
        } label: {
            EmptyView()
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .disabled(context.isReadOnly)
    }

    private func normalizeBooleanValue(_ val: String) -> String {
        let lower = val.lowercased()
        if lower == "true" || lower == "1" || lower == "t" || lower == "yes" {
            return "1"
        }
        return "0"
    }
}
