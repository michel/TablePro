import Testing
@testable import TablePro

@Suite("ColumnType.init(fromRedisType:)")
struct ColumnTypeRedisTests {

    @Test("string maps to .text with rawType String")
    func stringType() {
        #expect(ColumnType(fromRedisType: "string") == .text(rawType: "String"))
    }

    @Test("list maps to .json with rawType List")
    func listType() {
        #expect(ColumnType(fromRedisType: "list") == .json(rawType: "List"))
    }

    @Test("set maps to .json with rawType Set")
    func setType() {
        #expect(ColumnType(fromRedisType: "set") == .json(rawType: "Set"))
    }

    @Test("zset maps to .json with rawType Sorted Set")
    func zsetType() {
        #expect(ColumnType(fromRedisType: "zset") == .json(rawType: "Sorted Set"))
    }

    @Test("hash maps to .json with rawType Hash")
    func hashType() {
        #expect(ColumnType(fromRedisType: "hash") == .json(rawType: "Hash"))
    }

    @Test("stream maps to .json with rawType Stream")
    func streamType() {
        #expect(ColumnType(fromRedisType: "stream") == .json(rawType: "Stream"))
    }

    @Test("none maps to .text with rawType None")
    func noneType() {
        #expect(ColumnType(fromRedisType: "none") == .text(rawType: "None"))
    }

    @Test("unknown type falls through to .text with raw type preserved")
    func unknownType() {
        #expect(ColumnType(fromRedisType: "hyperloglog") == .text(rawType: "hyperloglog"))
    }

    @Test("case insensitivity: uppercase STRING")
    func uppercaseString() {
        #expect(ColumnType(fromRedisType: "STRING") == .text(rawType: "String"))
    }

    @Test("case insensitivity: mixed-case List")
    func mixedCaseList() {
        #expect(ColumnType(fromRedisType: "List") == .json(rawType: "List"))
    }

    @Test("case insensitivity: uppercase HASH")
    func uppercaseHash() {
        #expect(ColumnType(fromRedisType: "HASH") == .json(rawType: "Hash"))
    }
}
