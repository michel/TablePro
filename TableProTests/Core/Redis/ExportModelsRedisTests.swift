import Testing
@testable import TablePro

@Suite("ExportFormat.availableCases for Redis")
struct ExportModelsRedisTests {

    @Test("Redis available cases are csv, json, xlsx")
    func availableCases() {
        let cases = ExportFormat.availableCases(for: .redis)
        #expect(cases == [.csv, .json, .xlsx])
    }

    @Test("Redis does not include sql")
    func excludesSql() {
        let cases = ExportFormat.availableCases(for: .redis)
        #expect(!cases.contains(.sql))
    }

    @Test("Redis does not include mql")
    func excludesMql() {
        let cases = ExportFormat.availableCases(for: .redis)
        #expect(!cases.contains(.mql))
    }
}
