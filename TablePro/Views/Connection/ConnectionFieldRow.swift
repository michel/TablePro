//
//  ConnectionFieldRow.swift
//  TablePro
//

import SwiftUI
import TableProPluginKit

struct ConnectionFieldRow: View {
    let field: ConnectionField
    @Binding var value: String

    var body: some View {
        switch field.fieldType {
        case .text:
            TextField(
                field.label,
                text: $value,
                prompt: field.placeholder.isEmpty ? nil : Text(field.placeholder)
            )
        case .secure:
            SecureField(
                field.label,
                text: $value,
                prompt: field.placeholder.isEmpty ? nil : Text(field.placeholder)
            )
        case .dropdown(let options):
            Picker(field.label, selection: $value) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
        }
    }
}
