import Foundation
import Testing
@testable import TablePro

@Suite("RedisReply Computed Properties")
struct RedisReplyTests {

    // MARK: - stringValue

    @Test("string reply returns its value from stringValue")
    func stringReplyStringValue() {
        #expect(RedisReply.string("hello").stringValue == "hello")
    }

    @Test("string reply returns nil from intValue when non-numeric")
    func stringReplyIntValueNonNumeric() {
        #expect(RedisReply.string("hello").intValue == nil)
    }

    @Test("numeric string reply parses intValue")
    func numericStringReplyIntValue() {
        #expect(RedisReply.string("42").stringValue == "42")
        #expect(RedisReply.string("42").intValue == 42)
    }

    @Test("status reply returns its value from stringValue")
    func statusReplyStringValue() {
        #expect(RedisReply.status("OK").stringValue == "OK")
    }

    @Test("data reply with valid UTF-8 returns stringValue")
    func dataReplyValidUtf8() {
        let data = "hello".data(using: .utf8)!
        #expect(RedisReply.data(data).stringValue == "hello")
    }

    @Test("data reply with invalid UTF-8 returns nil stringValue")
    func dataReplyInvalidUtf8() {
        let data = Data([0xFF, 0xFE])
        #expect(RedisReply.data(data).stringValue == nil)
    }

    // MARK: - intValue

    @Test("integer reply returns its value from intValue")
    func integerReplyIntValue() {
        #expect(RedisReply.integer(100).intValue == 100)
    }

    @Test("integer reply returns nil from stringValue")
    func integerReplyStringValue() {
        #expect(RedisReply.integer(100).stringValue == nil)
    }

    // MARK: - error and null

    @Test("error reply returns nil for stringValue and intValue")
    func errorReplyReturnsNil() {
        let reply = RedisReply.error("ERR")
        #expect(reply.stringValue == nil)
        #expect(reply.intValue == nil)
    }

    @Test("null reply returns nil for stringValue and intValue")
    func nullReplyReturnsNil() {
        let reply = RedisReply.null
        #expect(reply.stringValue == nil)
        #expect(reply.intValue == nil)
    }

    // MARK: - stringArrayValue

    @Test("array of strings returns stringArrayValue")
    func arrayOfStringsReturnsStringArray() {
        let reply = RedisReply.array([.string("a"), .string("b")])
        #expect(reply.stringArrayValue == ["a", "b"])
    }

    @Test("mixed array skips non-string elements in stringArrayValue")
    func mixedArrayCompactMaps() {
        let reply = RedisReply.array([.string("a"), .integer(1)])
        #expect(reply.stringArrayValue == ["a"])
    }

    @Test("non-array reply returns nil for stringArrayValue")
    func nonArrayStringArrayValue() {
        #expect(RedisReply.string("test").stringArrayValue == nil)
    }

    // MARK: - arrayValue

    @Test("array reply returns inner items from arrayValue")
    func arrayReplyArrayValue() {
        let inner: [RedisReply] = [.string("a")]
        let reply = RedisReply.array(inner)
        let result = reply.arrayValue
        #expect(result?.count == 1)
    }

    @Test("non-array reply returns nil for arrayValue")
    func nonArrayArrayValue() {
        #expect(RedisReply.string("test").arrayValue == nil)
    }

    // MARK: - Additional Edge Cases

    @Test("Empty array returns empty stringArrayValue")
    func emptyArrayStringArrayValue() {
        let reply = RedisReply.array([])
        #expect(reply.stringArrayValue == [])
    }

    @Test("Status reply returns nil for intValue when non-numeric")
    func statusReplyIntValueNonNumeric() {
        #expect(RedisReply.status("OK").intValue == nil)
    }

    @Test("Status reply with numeric string returns nil for intValue")
    func statusReplyNumericIntValue() {
        // .status goes through the default branch in intValue, so returns nil
        #expect(RedisReply.status("200").intValue == nil)
    }

    @Test("Data reply with numeric UTF-8 returns nil for intValue")
    func dataReplyNumericIntValue() {
        // .data goes through the default branch in intValue, so returns nil
        let data = "42".data(using: .utf8)!
        #expect(RedisReply.data(data).intValue == nil)
    }
}
