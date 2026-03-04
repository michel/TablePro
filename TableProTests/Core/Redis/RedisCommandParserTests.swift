@testable import TablePro
import Testing

@Suite("Redis Command Parser")
struct RedisCommandParserTests {
    // MARK: - String Commands

    @Suite("String Commands")
    struct StringCommands {
        @Test("GET parses key")
        func parseGet() throws {
            let op = try RedisCommandParser.parse("GET mykey")
            guard case .get(let key) = op else {
                Issue.record("Expected GET"); return
            }
            #expect(key == "mykey")
        }

        @Test("GET missing key throws")
        func getMissingKey() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("GET")
            }
        }

        @Test("SET parses key and value")
        func parseSet() throws {
            let op = try RedisCommandParser.parse("SET mykey myvalue")
            guard case .set(let key, let value, let options) = op else {
                Issue.record("Expected SET"); return
            }
            #expect(key == "mykey")
            #expect(value == "myvalue")
            #expect(options == nil)
        }

        @Test("SET with EX option")
        func setWithEx() throws {
            let op = try RedisCommandParser.parse("SET mykey myvalue EX 60")
            guard case .set(_, _, let options) = op else {
                Issue.record("Expected SET"); return
            }
            #expect(options?.ex == 60)
            #expect(options?.px == nil)
            #expect(options?.nx == false)
            #expect(options?.xx == false)
        }

        @Test("SET with PX option")
        func setWithPx() throws {
            let op = try RedisCommandParser.parse("SET mykey myvalue PX 5000")
            guard case .set(_, _, let options) = op else {
                Issue.record("Expected SET"); return
            }
            #expect(options?.px == 5_000)
            #expect(options?.ex == nil)
        }

        @Test("SET with NX option")
        func setWithNx() throws {
            let op = try RedisCommandParser.parse("SET mykey myvalue NX")
            guard case .set(_, _, let options) = op else {
                Issue.record("Expected SET"); return
            }
            #expect(options?.nx == true)
            #expect(options?.xx == false)
        }

        @Test("SET with XX option")
        func setWithXx() throws {
            let op = try RedisCommandParser.parse("SET mykey myvalue XX")
            guard case .set(_, _, let options) = op else {
                Issue.record("Expected SET"); return
            }
            #expect(options?.xx == true)
            #expect(options?.nx == false)
        }

        @Test("SET with combined options EX and NX")
        func setWithExAndNx() throws {
            let op = try RedisCommandParser.parse("SET mykey myvalue EX 120 NX")
            guard case .set(_, _, let options) = op else {
                Issue.record("Expected SET"); return
            }
            #expect(options?.ex == 120)
            #expect(options?.nx == true)
        }

        @Test("SET missing value throws")
        func setMissingValue() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("SET mykey")
            }
        }

        @Test("SET missing key and value throws")
        func setMissingBoth() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("SET")
            }
        }

        @Test("DEL single key")
        func delSingleKey() throws {
            let op = try RedisCommandParser.parse("DEL key1")
            guard case .del(let keys) = op else {
                Issue.record("Expected DEL"); return
            }
            #expect(keys == ["key1"])
        }

        @Test("DEL multiple keys")
        func delMultipleKeys() throws {
            let op = try RedisCommandParser.parse("DEL key1 key2 key3")
            guard case .del(let keys) = op else {
                Issue.record("Expected DEL"); return
            }
            #expect(keys == ["key1", "key2", "key3"])
        }

        @Test("DEL missing key throws")
        func delMissingKey() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("DEL")
            }
        }
    }

    // MARK: - Key Commands

    @Suite("Key Commands")
    struct KeyCommands {
        @Test("KEYS parses pattern")
        func parseKeys() throws {
            let op = try RedisCommandParser.parse("KEYS user:*")
            guard case .keys(let pattern) = op else {
                Issue.record("Expected KEYS"); return
            }
            #expect(pattern == "user:*")
        }

        @Test("KEYS missing pattern throws")
        func keysMissingPattern() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("KEYS")
            }
        }

        @Test("SCAN with cursor only")
        func scanCursorOnly() throws {
            let op = try RedisCommandParser.parse("SCAN 0")
            guard case .scan(let cursor, let pattern, let count) = op else {
                Issue.record("Expected SCAN"); return
            }
            #expect(cursor == 0)
            #expect(pattern == nil)
            #expect(count == nil)
        }

        @Test("SCAN with MATCH option")
        func scanWithMatch() throws {
            let op = try RedisCommandParser.parse("SCAN 0 MATCH user:*")
            guard case .scan(let cursor, let pattern, let count) = op else {
                Issue.record("Expected SCAN"); return
            }
            #expect(cursor == 0)
            #expect(pattern == "user:*")
            #expect(count == nil)
        }

        @Test("SCAN with COUNT option")
        func scanWithCount() throws {
            let op = try RedisCommandParser.parse("SCAN 5 COUNT 200")
            guard case .scan(let cursor, let pattern, let count) = op else {
                Issue.record("Expected SCAN"); return
            }
            #expect(cursor == 5)
            #expect(pattern == nil)
            #expect(count == 200)
        }

        @Test("SCAN with MATCH and COUNT")
        func scanWithMatchAndCount() throws {
            let op = try RedisCommandParser.parse("SCAN 0 MATCH user:* COUNT 100")
            guard case .scan(let cursor, let pattern, let count) = op else {
                Issue.record("Expected SCAN"); return
            }
            #expect(cursor == 0)
            #expect(pattern == "user:*")
            #expect(count == 100)
        }

        @Test("SCAN with non-integer cursor throws")
        func scanInvalidCursor() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("SCAN abc")
            }
        }

        @Test("SCAN missing cursor throws")
        func scanMissingCursor() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("SCAN")
            }
        }

        @Test("TYPE parses key")
        func parseType() throws {
            let op = try RedisCommandParser.parse("TYPE mykey")
            guard case .type(let key) = op else {
                Issue.record("Expected TYPE"); return
            }
            #expect(key == "mykey")
        }

        @Test("TYPE missing key throws")
        func typeMissingKey() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("TYPE")
            }
        }

        @Test("TTL parses key")
        func parseTtl() throws {
            let op = try RedisCommandParser.parse("TTL session:abc")
            guard case .ttl(let key) = op else {
                Issue.record("Expected TTL"); return
            }
            #expect(key == "session:abc")
        }

        @Test("TTL missing key throws")
        func ttlMissingKey() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("TTL")
            }
        }

        @Test("PTTL parses key")
        func parsePttl() throws {
            let op = try RedisCommandParser.parse("PTTL session:abc")
            guard case .pttl(let key) = op else {
                Issue.record("Expected PTTL"); return
            }
            #expect(key == "session:abc")
        }

        @Test("PTTL missing key throws")
        func pttlMissingKey() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("PTTL")
            }
        }

        @Test("EXPIRE parses key and seconds")
        func parseExpire() throws {
            let op = try RedisCommandParser.parse("EXPIRE mykey 300")
            guard case .expire(let key, let seconds) = op else {
                Issue.record("Expected EXPIRE"); return
            }
            #expect(key == "mykey")
            #expect(seconds == 300)
        }

        @Test("EXPIRE with non-integer seconds throws")
        func expireInvalidSeconds() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("EXPIRE mykey abc")
            }
        }

        @Test("EXPIRE missing seconds throws")
        func expireMissingSeconds() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("EXPIRE mykey")
            }
        }

        @Test("PERSIST parses key")
        func parsePersist() throws {
            let op = try RedisCommandParser.parse("PERSIST mykey")
            guard case .persist(let key) = op else {
                Issue.record("Expected PERSIST"); return
            }
            #expect(key == "mykey")
        }

        @Test("PERSIST missing key throws")
        func persistMissingKey() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("PERSIST")
            }
        }

        @Test("RENAME parses key and newKey")
        func parseRename() throws {
            let op = try RedisCommandParser.parse("RENAME oldkey newkey")
            guard case .rename(let key, let newKey) = op else {
                Issue.record("Expected RENAME"); return
            }
            #expect(key == "oldkey")
            #expect(newKey == "newkey")
        }

        @Test("RENAME missing newKey throws")
        func renameMissingNewKey() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("RENAME oldkey")
            }
        }

        @Test("EXISTS single key")
        func existsSingleKey() throws {
            let op = try RedisCommandParser.parse("EXISTS mykey")
            guard case .exists(let keys) = op else {
                Issue.record("Expected EXISTS"); return
            }
            #expect(keys == ["mykey"])
        }

        @Test("EXISTS multiple keys")
        func existsMultipleKeys() throws {
            let op = try RedisCommandParser.parse("EXISTS key1 key2 key3")
            guard case .exists(let keys) = op else {
                Issue.record("Expected EXISTS"); return
            }
            #expect(keys == ["key1", "key2", "key3"])
        }

        @Test("EXISTS missing key throws")
        func existsMissingKey() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("EXISTS")
            }
        }
    }

    // MARK: - Hash Commands

    @Suite("Hash Commands")
    struct HashCommands {
        @Test("HGET parses key and field")
        func parseHget() throws {
            let op = try RedisCommandParser.parse("HGET myhash name")
            guard case .hget(let key, let field) = op else {
                Issue.record("Expected HGET"); return
            }
            #expect(key == "myhash")
            #expect(field == "name")
        }

        @Test("HGET missing field throws")
        func hgetMissingField() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("HGET myhash")
            }
        }

        @Test("HSET single field-value pair")
        func hsetSinglePair() throws {
            let op = try RedisCommandParser.parse("HSET myhash name Alice")
            guard case .hset(let key, let fieldValues) = op else {
                Issue.record("Expected HSET"); return
            }
            #expect(key == "myhash")
            #expect(fieldValues.count == 1)
            #expect(fieldValues[0].0 == "name")
            #expect(fieldValues[0].1 == "Alice")
        }

        @Test("HSET multiple field-value pairs")
        func hsetMultiplePairs() throws {
            let op = try RedisCommandParser.parse("HSET myhash name Alice age 30")
            guard case .hset(let key, let fieldValues) = op else {
                Issue.record("Expected HSET"); return
            }
            #expect(key == "myhash")
            #expect(fieldValues.count == 2)
            #expect(fieldValues[0].0 == "name")
            #expect(fieldValues[0].1 == "Alice")
            #expect(fieldValues[1].0 == "age")
            #expect(fieldValues[1].1 == "30")
        }

        @Test("HSET with even arg count (odd field-values) throws")
        func hsetOddArgCount() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("HSET myhash name Alice age")
            }
        }

        @Test("HSET missing field-value throws")
        func hsetMissingFieldValue() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("HSET myhash")
            }
        }

        @Test("HGETALL parses key")
        func parseHgetall() throws {
            let op = try RedisCommandParser.parse("HGETALL myhash")
            guard case .hgetall(let key) = op else {
                Issue.record("Expected HGETALL"); return
            }
            #expect(key == "myhash")
        }

        @Test("HGETALL missing key throws")
        func hgetallMissingKey() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("HGETALL")
            }
        }

        @Test("HDEL single field")
        func hdelSingleField() throws {
            let op = try RedisCommandParser.parse("HDEL myhash name")
            guard case .hdel(let key, let fields) = op else {
                Issue.record("Expected HDEL"); return
            }
            #expect(key == "myhash")
            #expect(fields == ["name"])
        }

        @Test("HDEL multiple fields")
        func hdelMultipleFields() throws {
            let op = try RedisCommandParser.parse("HDEL myhash name age email")
            guard case .hdel(let key, let fields) = op else {
                Issue.record("Expected HDEL"); return
            }
            #expect(key == "myhash")
            #expect(fields == ["name", "age", "email"])
        }

        @Test("HDEL missing field throws")
        func hdelMissingField() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("HDEL myhash")
            }
        }
    }

    // MARK: - List Commands

    @Suite("List Commands")
    struct ListCommands {
        @Test("LRANGE parses key, start, stop")
        func parseLrange() throws {
            let op = try RedisCommandParser.parse("LRANGE mylist 0 -1")
            guard case .lrange(let key, let start, let stop) = op else {
                Issue.record("Expected LRANGE"); return
            }
            #expect(key == "mylist")
            #expect(start == 0)
            #expect(stop == -1)
        }

        @Test("LRANGE with positive range")
        func lrangePositiveRange() throws {
            let op = try RedisCommandParser.parse("LRANGE mylist 5 10")
            guard case .lrange(_, let start, let stop) = op else {
                Issue.record("Expected LRANGE"); return
            }
            #expect(start == 5)
            #expect(stop == 10)
        }

        @Test("LRANGE with non-integer start throws")
        func lrangeInvalidStart() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("LRANGE mylist abc -1")
            }
        }

        @Test("LRANGE with non-integer stop throws")
        func lrangeInvalidStop() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("LRANGE mylist 0 xyz")
            }
        }

        @Test("LRANGE missing arguments throws")
        func lrangeMissingArgs() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("LRANGE mylist")
            }
        }

        @Test("LPUSH single value")
        func lpushSingleValue() throws {
            let op = try RedisCommandParser.parse("LPUSH mylist val1")
            guard case .lpush(let key, let values) = op else {
                Issue.record("Expected LPUSH"); return
            }
            #expect(key == "mylist")
            #expect(values == ["val1"])
        }

        @Test("LPUSH multiple values")
        func lpushMultipleValues() throws {
            let op = try RedisCommandParser.parse("LPUSH mylist val1 val2 val3")
            guard case .lpush(let key, let values) = op else {
                Issue.record("Expected LPUSH"); return
            }
            #expect(key == "mylist")
            #expect(values == ["val1", "val2", "val3"])
        }

        @Test("LPUSH missing value throws")
        func lpushMissingValue() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("LPUSH mylist")
            }
        }

        @Test("RPUSH single value")
        func rpushSingleValue() throws {
            let op = try RedisCommandParser.parse("RPUSH mylist val1")
            guard case .rpush(let key, let values) = op else {
                Issue.record("Expected RPUSH"); return
            }
            #expect(key == "mylist")
            #expect(values == ["val1"])
        }

        @Test("RPUSH multiple values")
        func rpushMultipleValues() throws {
            let op = try RedisCommandParser.parse("RPUSH mylist val1 val2 val3")
            guard case .rpush(let key, let values) = op else {
                Issue.record("Expected RPUSH"); return
            }
            #expect(key == "mylist")
            #expect(values == ["val1", "val2", "val3"])
        }

        @Test("RPUSH missing value throws")
        func rpushMissingValue() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("RPUSH mylist")
            }
        }

        @Test("LLEN parses key")
        func parseLlen() throws {
            let op = try RedisCommandParser.parse("LLEN mylist")
            guard case .llen(let key) = op else {
                Issue.record("Expected LLEN"); return
            }
            #expect(key == "mylist")
        }

        @Test("LLEN missing key throws")
        func llenMissingKey() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("LLEN")
            }
        }
    }

    // MARK: - Set Commands

    @Suite("Set Commands")
    struct SetCommands {
        @Test("SMEMBERS parses key")
        func parseSmembers() throws {
            let op = try RedisCommandParser.parse("SMEMBERS myset")
            guard case .smembers(let key) = op else {
                Issue.record("Expected SMEMBERS"); return
            }
            #expect(key == "myset")
        }

        @Test("SMEMBERS missing key throws")
        func smembersMissingKey() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("SMEMBERS")
            }
        }

        @Test("SADD single member")
        func saddSingleMember() throws {
            let op = try RedisCommandParser.parse("SADD myset member1")
            guard case .sadd(let key, let members) = op else {
                Issue.record("Expected SADD"); return
            }
            #expect(key == "myset")
            #expect(members == ["member1"])
        }

        @Test("SADD multiple members")
        func saddMultipleMembers() throws {
            let op = try RedisCommandParser.parse("SADD myset m1 m2 m3")
            guard case .sadd(let key, let members) = op else {
                Issue.record("Expected SADD"); return
            }
            #expect(key == "myset")
            #expect(members == ["m1", "m2", "m3"])
        }

        @Test("SADD missing member throws")
        func saddMissingMember() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("SADD myset")
            }
        }

        @Test("SREM single member")
        func sremSingleMember() throws {
            let op = try RedisCommandParser.parse("SREM myset member1")
            guard case .srem(let key, let members) = op else {
                Issue.record("Expected SREM"); return
            }
            #expect(key == "myset")
            #expect(members == ["member1"])
        }

        @Test("SREM multiple members")
        func sremMultipleMembers() throws {
            let op = try RedisCommandParser.parse("SREM myset m1 m2 m3")
            guard case .srem(let key, let members) = op else {
                Issue.record("Expected SREM"); return
            }
            #expect(key == "myset")
            #expect(members == ["m1", "m2", "m3"])
        }

        @Test("SREM missing member throws")
        func sremMissingMember() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("SREM myset")
            }
        }

        @Test("SCARD parses key")
        func parseScard() throws {
            let op = try RedisCommandParser.parse("SCARD myset")
            guard case .scard(let key) = op else {
                Issue.record("Expected SCARD"); return
            }
            #expect(key == "myset")
        }

        @Test("SCARD missing key throws")
        func scardMissingKey() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("SCARD")
            }
        }
    }

    // MARK: - Sorted Set Commands

    @Suite("Sorted Set Commands")
    struct SortedSetCommands {
        @Test("ZRANGE without WITHSCORES")
        func zrangeWithoutScores() throws {
            let op = try RedisCommandParser.parse("ZRANGE myzset 0 -1")
            guard case .zrange(let key, let start, let stop, let withScores) = op else {
                Issue.record("Expected ZRANGE"); return
            }
            #expect(key == "myzset")
            #expect(start == 0)
            #expect(stop == -1)
            #expect(withScores == false)
        }

        @Test("ZRANGE with WITHSCORES")
        func zrangeWithScores() throws {
            let op = try RedisCommandParser.parse("ZRANGE myzset 0 -1 WITHSCORES")
            guard case .zrange(let key, let start, let stop, let withScores) = op else {
                Issue.record("Expected ZRANGE"); return
            }
            #expect(key == "myzset")
            #expect(start == 0)
            #expect(stop == -1)
            #expect(withScores == true)
        }

        @Test("ZRANGE with non-integer start throws")
        func zrangeInvalidStart() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("ZRANGE myzset abc -1")
            }
        }

        @Test("ZRANGE with non-integer stop throws")
        func zrangeInvalidStop() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("ZRANGE myzset 0 xyz")
            }
        }

        @Test("ZRANGE missing arguments throws")
        func zrangeMissingArgs() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("ZRANGE myzset")
            }
        }

        @Test("ZADD single score-member pair")
        func zaddSinglePair() throws {
            let op = try RedisCommandParser.parse("ZADD myzset 1.5 member1")
            guard case .zadd(let key, let scoreMembers) = op else {
                Issue.record("Expected ZADD"); return
            }
            #expect(key == "myzset")
            #expect(scoreMembers.count == 1)
            #expect(scoreMembers[0].0 == 1.5)
            #expect(scoreMembers[0].1 == "member1")
        }

        @Test("ZADD multiple score-member pairs")
        func zaddMultiplePairs() throws {
            let op = try RedisCommandParser.parse("ZADD myzset 1.0 alpha 2.0 beta 3.0 gamma")
            guard case .zadd(let key, let scoreMembers) = op else {
                Issue.record("Expected ZADD"); return
            }
            #expect(key == "myzset")
            #expect(scoreMembers.count == 3)
            #expect(scoreMembers[0].0 == 1.0)
            #expect(scoreMembers[0].1 == "alpha")
            #expect(scoreMembers[1].0 == 2.0)
            #expect(scoreMembers[1].1 == "beta")
            #expect(scoreMembers[2].0 == 3.0)
            #expect(scoreMembers[2].1 == "gamma")
        }

        @Test("ZADD with integer score")
        func zaddIntegerScore() throws {
            let op = try RedisCommandParser.parse("ZADD myzset 5 member1")
            guard case .zadd(_, let scoreMembers) = op else {
                Issue.record("Expected ZADD"); return
            }
            #expect(scoreMembers[0].0 == 5.0)
        }

        @Test("ZADD with invalid score throws")
        func zaddInvalidScore() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("ZADD myzset notanumber member1")
            }
        }

        @Test("ZADD with odd score-member count throws")
        func zaddOddPairCount() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("ZADD myzset 1.0 alpha 2.0")
            }
        }

        @Test("ZADD missing score-member throws")
        func zaddMissingArgs() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("ZADD myzset")
            }
        }

        @Test("ZREM single member")
        func zremSingleMember() throws {
            let op = try RedisCommandParser.parse("ZREM myzset member1")
            guard case .zrem(let key, let members) = op else {
                Issue.record("Expected ZREM"); return
            }
            #expect(key == "myzset")
            #expect(members == ["member1"])
        }

        @Test("ZREM multiple members")
        func zremMultipleMembers() throws {
            let op = try RedisCommandParser.parse("ZREM myzset m1 m2 m3")
            guard case .zrem(let key, let members) = op else {
                Issue.record("Expected ZREM"); return
            }
            #expect(key == "myzset")
            #expect(members == ["m1", "m2", "m3"])
        }

        @Test("ZREM missing member throws")
        func zremMissingMember() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("ZREM myzset")
            }
        }

        @Test("ZCARD parses key")
        func parseZcard() throws {
            let op = try RedisCommandParser.parse("ZCARD myzset")
            guard case .zcard(let key) = op else {
                Issue.record("Expected ZCARD"); return
            }
            #expect(key == "myzset")
        }

        @Test("ZCARD missing key throws")
        func zcardMissingKey() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("ZCARD")
            }
        }
    }

    // MARK: - Stream Commands

    @Suite("Stream Commands")
    struct StreamCommands {
        @Test("XRANGE without COUNT")
        func xrangeWithoutCount() throws {
            let op = try RedisCommandParser.parse("XRANGE mystream - +")
            guard case .xrange(let key, let start, let end, let count) = op else {
                Issue.record("Expected XRANGE"); return
            }
            #expect(key == "mystream")
            #expect(start == "-")
            #expect(end == "+")
            #expect(count == nil)
        }

        @Test("XRANGE with COUNT")
        func xrangeWithCount() throws {
            let op = try RedisCommandParser.parse("XRANGE mystream - + COUNT 10")
            guard case .xrange(let key, let start, let end, let count) = op else {
                Issue.record("Expected XRANGE"); return
            }
            #expect(key == "mystream")
            #expect(start == "-")
            #expect(end == "+")
            #expect(count == 10)
        }

        @Test("XRANGE with specific IDs")
        func xrangeWithIds() throws {
            let op = try RedisCommandParser.parse("XRANGE mystream 1526985054069-0 1526985055069-0")
            guard case .xrange(_, let start, let end, _) = op else {
                Issue.record("Expected XRANGE"); return
            }
            #expect(start == "1526985054069-0")
            #expect(end == "1526985055069-0")
        }

        @Test("XRANGE missing arguments throws")
        func xrangeMissingArgs() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("XRANGE mystream")
            }
        }

        @Test("XLEN parses key")
        func parseXlen() throws {
            let op = try RedisCommandParser.parse("XLEN mystream")
            guard case .xlen(let key) = op else {
                Issue.record("Expected XLEN"); return
            }
            #expect(key == "mystream")
        }

        @Test("XLEN missing key throws")
        func xlenMissingKey() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("XLEN")
            }
        }
    }

    // MARK: - Server Commands

    @Suite("Server Commands")
    struct ServerCommands {
        @Test("PING")
        func parsePing() throws {
            let op = try RedisCommandParser.parse("PING")
            guard case .ping = op else {
                Issue.record("Expected PING"); return
            }
        }

        @Test("INFO without section")
        func infoWithoutSection() throws {
            let op = try RedisCommandParser.parse("INFO")
            guard case .info(let section) = op else {
                Issue.record("Expected INFO"); return
            }
            #expect(section == nil)
        }

        @Test("INFO with section")
        func infoWithSection() throws {
            let op = try RedisCommandParser.parse("INFO server")
            guard case .info(let section) = op else {
                Issue.record("Expected INFO"); return
            }
            #expect(section == "server")
        }

        @Test("DBSIZE")
        func parseDbsize() throws {
            let op = try RedisCommandParser.parse("DBSIZE")
            guard case .dbsize = op else {
                Issue.record("Expected DBSIZE"); return
            }
        }

        @Test("FLUSHDB")
        func parseFlushdb() throws {
            let op = try RedisCommandParser.parse("FLUSHDB")
            guard case .flushdb = op else {
                Issue.record("Expected FLUSHDB"); return
            }
        }

        @Test("SELECT valid database index")
        func parseSelect() throws {
            let op = try RedisCommandParser.parse("SELECT 3")
            guard case .select(let database) = op else {
                Issue.record("Expected SELECT"); return
            }
            #expect(database == 3)
        }

        @Test("SELECT with non-integer throws")
        func selectInvalidIndex() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("SELECT abc")
            }
        }

        @Test("SELECT missing index throws")
        func selectMissingIndex() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("SELECT")
            }
        }

        @Test("CONFIG GET parses parameter")
        func parseConfigGet() throws {
            let op = try RedisCommandParser.parse("CONFIG GET maxmemory")
            guard case .configGet(let parameter) = op else {
                Issue.record("Expected CONFIG GET"); return
            }
            #expect(parameter == "maxmemory")
        }

        @Test("CONFIG SET parses parameter and value")
        func parseConfigSet() throws {
            let op = try RedisCommandParser.parse("CONFIG SET maxmemory 128mb")
            guard case .configSet(let parameter, let value) = op else {
                Issue.record("Expected CONFIG SET"); return
            }
            #expect(parameter == "maxmemory")
            #expect(value == "128mb")
        }

        @Test("CONFIG SET missing value throws")
        func configSetMissingValue() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("CONFIG SET maxmemory")
            }
        }

        @Test("CONFIG missing subcommand throws")
        func configMissingSubcommand() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("CONFIG")
            }
        }

        @Test("CONFIG with only one arg throws (requires subcommand + parameter)")
        func configUnknownSubcommand() {
            // CONFIG requires at least 2 args (subcommand + parameter), so CONFIG RESETSTAT throws
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("CONFIG RESETSTAT")
            }
        }

        @Test("CONFIG unknown subcommand with parameter falls back to .command")
        func configUnknownSubcommandWithParam() throws {
            let op = try RedisCommandParser.parse("CONFIG RESETSTAT all")
            guard case .command(let args) = op else {
                Issue.record("Expected .command fallback"); return
            }
            #expect(args == ["CONFIG", "RESETSTAT", "all"])
        }
    }

    // MARK: - Transaction Commands

    @Suite("Transaction Commands")
    struct TransactionCommands {
        @Test("MULTI")
        func parseMulti() throws {
            let op = try RedisCommandParser.parse("MULTI")
            guard case .multi = op else {
                Issue.record("Expected MULTI"); return
            }
        }

        @Test("EXEC")
        func parseExec() throws {
            let op = try RedisCommandParser.parse("EXEC")
            guard case .exec = op else {
                Issue.record("Expected EXEC"); return
            }
        }

        @Test("DISCARD")
        func parseDiscard() throws {
            let op = try RedisCommandParser.parse("DISCARD")
            guard case .discard = op else {
                Issue.record("Expected DISCARD"); return
            }
        }
    }

    // MARK: - Error Cases

    @Suite("Error Cases")
    struct ErrorCases {
        @Test("Empty string throws emptySyntax")
        func emptyInput() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("")
            }
        }

        @Test("Whitespace-only string throws emptySyntax")
        func whitespaceOnlyInput() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("   ")
            }
        }

        @Test("EXPIRE non-integer seconds throws invalidArgument")
        func expireNonInteger() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("EXPIRE key 3.5")
            }
        }

        @Test("LRANGE non-integer indices throws invalidArgument")
        func lrangeNonInteger() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("LRANGE list a b")
            }
        }

        @Test("ZRANGE non-integer indices throws invalidArgument")
        func zrangeNonInteger() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("ZRANGE zset a b")
            }
        }

        @Test("SCAN non-integer cursor throws missingArgument")
        func scanNonIntegerCursor() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("SCAN notint")
            }
        }

        @Test("SELECT non-integer database throws missingArgument")
        func selectNonInteger() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("SELECT notint")
            }
        }

        @Test("ZADD non-numeric score throws invalidArgument")
        func zaddNonNumericScore() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("ZADD zset abc member")
            }
        }

        @Test("HSET with only key throws missingArgument")
        func hsetOnlyKey() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("HSET hash")
            }
        }

        @Test("HDEL with only key throws missingArgument")
        func hdelOnlyKey() {
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("HDEL hash")
            }
        }
    }

    // MARK: - Tokenizer

    @Suite("Tokenizer")
    struct Tokenizer {
        @Test("Double-quoted strings preserve spaces")
        func doubleQuotedStrings() throws {
            let op = try RedisCommandParser.parse("SET \"my key\" \"my value\"")
            guard case .set(let key, let value, _) = op else {
                Issue.record("Expected SET"); return
            }
            #expect(key == "my key")
            #expect(value == "my value")
        }

        @Test("Single-quoted strings preserve spaces")
        func singleQuotedStrings() throws {
            let op = try RedisCommandParser.parse("SET 'my key' 'my value'")
            guard case .set(let key, let value, _) = op else {
                Issue.record("Expected SET"); return
            }
            #expect(key == "my key")
            #expect(value == "my value")
        }

        @Test("Escaped characters within unquoted tokens")
        func escapedCharacters() throws {
            let op = try RedisCommandParser.parse("SET my\\ key my\\ value")
            guard case .set(let key, let value, _) = op else {
                Issue.record("Expected SET"); return
            }
            #expect(key == "my key")
            #expect(value == "my value")
        }

        @Test("Escaped quote inside double-quoted string")
        func escapedQuoteInDoubleQuotes() throws {
            let op = try RedisCommandParser.parse("SET key \"val\\\"ue\"")
            guard case .set(_, let value, _) = op else {
                Issue.record("Expected SET"); return
            }
            #expect(value == "val\"ue")
        }

        @Test("Case-insensitive command parsing")
        func caseInsensitiveCommands() throws {
            let lower = try RedisCommandParser.parse("get mykey")
            guard case .get(let key1) = lower else {
                Issue.record("Expected GET from lowercase"); return
            }
            #expect(key1 == "mykey")

            let mixed = try RedisCommandParser.parse("GeT mykey")
            guard case .get(let key2) = mixed else {
                Issue.record("Expected GET from mixed case"); return
            }
            #expect(key2 == "mykey")
        }

        @Test("Unknown command falls back to .command with all tokens")
        func unknownCommandFallback() throws {
            let op = try RedisCommandParser.parse("CUSTOM arg1 arg2")
            guard case .command(let args) = op else {
                Issue.record("Expected generic command"); return
            }
            #expect(args == ["CUSTOM", "arg1", "arg2"])
        }

        @Test("Multiple spaces between tokens are handled")
        func multipleSpaces() throws {
            let op = try RedisCommandParser.parse("GET    mykey")
            guard case .get(let key) = op else {
                Issue.record("Expected GET"); return
            }
            #expect(key == "mykey")
        }

        @Test("Leading and trailing whitespace is trimmed")
        func leadingTrailingWhitespace() throws {
            let op = try RedisCommandParser.parse("  GET mykey  ")
            guard case .get(let key) = op else {
                Issue.record("Expected GET"); return
            }
            #expect(key == "mykey")
        }

        @Test("Empty quoted string is not appended as token")
        func emptyQuotedString() {
            // The tokenizer skips empty strings, so SET key "" only produces ["SET", "key"]
            #expect(throws: RedisParseError.self) {
                try RedisCommandParser.parse("SET key \"\"")
            }
        }
    }
}
