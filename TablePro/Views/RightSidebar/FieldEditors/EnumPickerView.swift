//
//  EnumPickerView.swift
//  TablePro
//

import SwiftUI

internal struct EnumPickerView: View {
    let context: FieldEditorContext
    let values: [String]

    var body: some View {
        Picker(selection: context.value) {
            ForEach(values, id: \.self) { val in
                Text(val).tag(val)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .disabled(context.isReadOnly)
    }
}
