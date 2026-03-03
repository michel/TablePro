//
//  DataGridSettingsTests.swift
//  TableProTests
//
//  Tests for DataGridSettings autoShowInspector field.
//

import Foundation
@testable import TablePro
import Testing

@Suite("DataGridSettings")
struct DataGridSettingsTests {
    @Test("autoShowInspector defaults to false")
    func defaultValue() {
        let settings = DataGridSettings.default
        #expect(settings.autoShowInspector == false)
    }

    @Test("autoShowInspector round-trips through Codable")
    func codableRoundTrip() throws {
        var settings = DataGridSettings.default
        settings.autoShowInspector = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DataGridSettings.self, from: data)
        #expect(decoded.autoShowInspector == true)
    }

    @Test("decoding without autoShowInspector key defaults to false")
    func backwardsCompatibility() throws {
        let oldJson = """
        {
            "rowHeight": 24,
            "dateFormat": "yyyy-MM-dd HH:mm:ss",
            "nullDisplay": "NULL",
            "defaultPageSize": 1000,
            "showAlternateRows": true
        }
        """
        let data = oldJson.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DataGridSettings.self, from: data)
        #expect(decoded.autoShowInspector == false)
    }
}
