import Foundation
import TableProPluginKit
import Testing

@Suite("ConnectionField")
struct ConnectionFieldTests {

    @Test("Default values: placeholder, isRequired, defaultValue, fieldType")
    func defaultValues() {
        let field = ConnectionField(id: "host", label: "Host")

        #expect(field.placeholder == "")
        #expect(field.isRequired == false)
        #expect(field.defaultValue == nil)
        #expect(field.fieldType == .text)
    }

    @Test("isSecure is false for .text")
    func isSecureForText() {
        let field = ConnectionField(id: "host", label: "Host", fieldType: .text)
        #expect(field.isSecure == false)
    }

    @Test("isSecure is true for .secure")
    func isSecureForSecure() {
        let field = ConnectionField(id: "pass", label: "Password", fieldType: .secure)
        #expect(field.isSecure == true)
    }

    @Test("isSecure is false for .dropdown")
    func isSecureForDropdown() {
        let options = [ConnectionField.DropdownOption(value: "a", label: "A")]
        let field = ConnectionField(id: "mode", label: "Mode", fieldType: .dropdown(options: options))
        #expect(field.isSecure == false)
    }

    @Test("secure param sets fieldType to .secure")
    func secureParam() {
        let field = ConnectionField(id: "pass", label: "Password", secure: true)
        #expect(field.fieldType == .secure)
        #expect(field.isSecure == true)
    }

    @Test("Explicit fieldType overrides secure param")
    func fieldTypeOverridesSecureParam() {
        let options = [ConnectionField.DropdownOption(value: "v", label: "V")]
        let field = ConnectionField(
            id: "mode",
            label: "Mode",
            secure: true,
            fieldType: .dropdown(options: options)
        )
        #expect(field.fieldType == .dropdown(options: options))
        #expect(field.isSecure == false)
    }

    @Test("DropdownOption stores value and label")
    func dropdownOption() {
        let option = ConnectionField.DropdownOption(value: "utf8", label: "UTF-8")
        #expect(option.value == "utf8")
        #expect(option.label == "UTF-8")
    }

    @Test("All properties stored correctly")
    func allPropertiesStored() {
        let field = ConnectionField(
            id: "port",
            label: "Port",
            placeholder: "3306",
            required: true,
            defaultValue: "3306",
            fieldType: .text
        )

        #expect(field.id == "port")
        #expect(field.label == "Port")
        #expect(field.placeholder == "3306")
        #expect(field.isRequired == true)
        #expect(field.defaultValue == "3306")
        #expect(field.fieldType == .text)
    }

    @Test("Codable round-trip for .text field")
    func codableText() throws {
        let field = ConnectionField(
            id: "host",
            label: "Host",
            placeholder: "localhost",
            required: true,
            defaultValue: "127.0.0.1",
            fieldType: .text
        )

        let data = try JSONEncoder().encode(field)
        let decoded = try JSONDecoder().decode(ConnectionField.self, from: data)

        #expect(decoded.id == field.id)
        #expect(decoded.label == field.label)
        #expect(decoded.placeholder == field.placeholder)
        #expect(decoded.isRequired == field.isRequired)
        #expect(decoded.defaultValue == field.defaultValue)
        #expect(decoded.fieldType == .text)
    }

    @Test("Codable round-trip for .secure field")
    func codableSecure() throws {
        let field = ConnectionField(
            id: "password",
            label: "Password",
            required: true,
            fieldType: .secure
        )

        let data = try JSONEncoder().encode(field)
        let decoded = try JSONDecoder().decode(ConnectionField.self, from: data)

        #expect(decoded.id == field.id)
        #expect(decoded.label == field.label)
        #expect(decoded.isRequired == field.isRequired)
        #expect(decoded.fieldType == .secure)
    }

    @Test("Codable round-trip for .dropdown field with options")
    func codableDropdown() throws {
        let options = [
            ConnectionField.DropdownOption(value: "utf8", label: "UTF-8"),
            ConnectionField.DropdownOption(value: "latin1", label: "Latin 1"),
        ]
        let field = ConnectionField(
            id: "charset",
            label: "Charset",
            defaultValue: "utf8",
            fieldType: .dropdown(options: options)
        )

        let data = try JSONEncoder().encode(field)
        let decoded = try JSONDecoder().decode(ConnectionField.self, from: data)

        #expect(decoded.id == field.id)
        #expect(decoded.label == field.label)
        #expect(decoded.defaultValue == field.defaultValue)
        #expect(decoded.fieldType == .dropdown(options: options))
    }

    @Test("Codable round-trip with nil defaultValue")
    func codableNilDefaultValue() throws {
        let field = ConnectionField(id: "host", label: "Host")

        let data = try JSONEncoder().encode(field)
        let decoded = try JSONDecoder().decode(ConnectionField.self, from: data)

        #expect(decoded.defaultValue == nil)
        #expect(decoded.id == field.id)
        #expect(decoded.fieldType == .text)
    }
}
