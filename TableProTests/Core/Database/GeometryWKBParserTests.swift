//
//  GeometryWKBParserTests.swift
//  TableProTests
//
//  Tests for GeometryWKBParser WKB binary to WKT string conversion.
//

import Foundation
@testable import TablePro
import Testing

@Suite("Geometry WKB Parser")
struct GeometryWKBParserTests {
    // MARK: - Helper

    private func buildMySQLGeometry(srid: UInt32 = 0, wkb: [UInt8]) -> Data {
        var data = Data()
        var sridLE = srid.littleEndian
        data.append(Data(bytes: &sridLE, count: 4))
        data.append(contentsOf: wkb)
        return data
    }

    private func wkbPoint(x: Double, y: Double, littleEndian: Bool = true) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.append(littleEndian ? 0x01 : 0x00)
        appendUInt32(&bytes, value: 1, littleEndian: littleEndian)
        appendFloat64(&bytes, value: x, littleEndian: littleEndian)
        appendFloat64(&bytes, value: y, littleEndian: littleEndian)
        return bytes
    }

    private func appendUInt32(_ bytes: inout [UInt8], value: UInt32, littleEndian: Bool) {
        if littleEndian {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { bytes.append(contentsOf: $0) }
        } else {
            var v = value.bigEndian
            withUnsafeBytes(of: &v) { bytes.append(contentsOf: $0) }
        }
    }

    private func appendFloat64(_ bytes: inout [UInt8], value: Double, littleEndian: Bool) {
        let bits = value.bitPattern
        if littleEndian {
            var v = bits.littleEndian
            withUnsafeBytes(of: &v) { bytes.append(contentsOf: $0) }
        } else {
            var v = bits.bigEndian
            withUnsafeBytes(of: &v) { bytes.append(contentsOf: $0) }
        }
    }

    // MARK: - POINT Parsing

    @Test("Valid WKB POINT with SRID=0")
    func pointSrid0() {
        let data = buildMySQLGeometry(srid: 0, wkb: wkbPoint(x: 1.0, y: 2.0))
        let result = GeometryWKBParser.parse(data)
        #expect(result == "POINT(1.0 2.0)")
    }

    @Test("Valid WKB POINT with non-zero SRID")
    func pointNonZeroSrid() {
        let data = buildMySQLGeometry(srid: 4_326, wkb: wkbPoint(x: 103.8, y: 1.35))
        let result = GeometryWKBParser.parse(data)
        #expect(result == "POINT(103.8 1.35)")
    }

    @Test("POINT with negative coordinates")
    func pointNegativeCoords() {
        let data = buildMySQLGeometry(srid: 0, wkb: wkbPoint(x: -73.9857, y: 40.7484))
        let result = GeometryWKBParser.parse(data)
        #expect(result == "POINT(-73.9857 40.7484)")
    }

    @Test("POINT with zero coordinates")
    func pointZeroCoords() {
        let data = buildMySQLGeometry(srid: 0, wkb: wkbPoint(x: 0.0, y: 0.0))
        let result = GeometryWKBParser.parse(data)
        #expect(result == "POINT(0.0 0.0)")
    }

    @Test("POINT with big-endian byte order")
    func pointBigEndian() {
        let data = buildMySQLGeometry(srid: 0, wkb: wkbPoint(x: 1.0, y: 2.0, littleEndian: false))
        let result = GeometryWKBParser.parse(data)
        #expect(result == "POINT(1.0 2.0)")
    }

    // MARK: - LINESTRING Parsing

    @Test("Valid WKB LINESTRING with 2 points")
    func lineString2Points() {
        var wkb: [UInt8] = [0x01]
        appendUInt32(&wkb, value: 2, littleEndian: true)
        appendUInt32(&wkb, value: 2, littleEndian: true)
        appendFloat64(&wkb, value: 0.0, littleEndian: true)
        appendFloat64(&wkb, value: 0.0, littleEndian: true)
        appendFloat64(&wkb, value: 1.0, littleEndian: true)
        appendFloat64(&wkb, value: 1.0, littleEndian: true)

        let data = buildMySQLGeometry(wkb: wkb)
        let result = GeometryWKBParser.parse(data)
        #expect(result == "LINESTRING(0.0 0.0, 1.0 1.0)")
    }

    @Test("Valid WKB LINESTRING with 3 points")
    func lineString3Points() {
        var wkb: [UInt8] = [0x01]
        appendUInt32(&wkb, value: 2, littleEndian: true)
        appendUInt32(&wkb, value: 3, littleEndian: true)
        appendFloat64(&wkb, value: 0.0, littleEndian: true)
        appendFloat64(&wkb, value: 0.0, littleEndian: true)
        appendFloat64(&wkb, value: 1.0, littleEndian: true)
        appendFloat64(&wkb, value: 1.0, littleEndian: true)
        appendFloat64(&wkb, value: 2.0, littleEndian: true)
        appendFloat64(&wkb, value: 0.0, littleEndian: true)

        let data = buildMySQLGeometry(wkb: wkb)
        let result = GeometryWKBParser.parse(data)
        #expect(result == "LINESTRING(0.0 0.0, 1.0 1.0, 2.0 0.0)")
    }

    // MARK: - POLYGON Parsing

    @Test("Valid WKB POLYGON with 1 ring")
    func polygon1Ring() {
        var wkb: [UInt8] = [0x01]
        appendUInt32(&wkb, value: 3, littleEndian: true)
        appendUInt32(&wkb, value: 1, littleEndian: true)
        appendUInt32(&wkb, value: 4, littleEndian: true)
        appendFloat64(&wkb, value: 0.0, littleEndian: true)
        appendFloat64(&wkb, value: 0.0, littleEndian: true)
        appendFloat64(&wkb, value: 1.0, littleEndian: true)
        appendFloat64(&wkb, value: 0.0, littleEndian: true)
        appendFloat64(&wkb, value: 1.0, littleEndian: true)
        appendFloat64(&wkb, value: 1.0, littleEndian: true)
        appendFloat64(&wkb, value: 0.0, littleEndian: true)
        appendFloat64(&wkb, value: 0.0, littleEndian: true)

        let data = buildMySQLGeometry(wkb: wkb)
        let result = GeometryWKBParser.parse(data)
        #expect(result == "POLYGON((0.0 0.0, 1.0 0.0, 1.0 1.0, 0.0 0.0))")
    }

    @Test("Valid WKB POLYGON with 2 rings")
    func polygon2Rings() {
        var wkb: [UInt8] = [0x01]
        appendUInt32(&wkb, value: 3, littleEndian: true)
        appendUInt32(&wkb, value: 2, littleEndian: true)

        // Outer ring: 4 points
        appendUInt32(&wkb, value: 4, littleEndian: true)
        appendFloat64(&wkb, value: 0.0, littleEndian: true)
        appendFloat64(&wkb, value: 0.0, littleEndian: true)
        appendFloat64(&wkb, value: 10.0, littleEndian: true)
        appendFloat64(&wkb, value: 0.0, littleEndian: true)
        appendFloat64(&wkb, value: 10.0, littleEndian: true)
        appendFloat64(&wkb, value: 10.0, littleEndian: true)
        appendFloat64(&wkb, value: 0.0, littleEndian: true)
        appendFloat64(&wkb, value: 0.0, littleEndian: true)

        // Inner ring (hole): 4 points
        appendUInt32(&wkb, value: 4, littleEndian: true)
        appendFloat64(&wkb, value: 2.0, littleEndian: true)
        appendFloat64(&wkb, value: 2.0, littleEndian: true)
        appendFloat64(&wkb, value: 8.0, littleEndian: true)
        appendFloat64(&wkb, value: 2.0, littleEndian: true)
        appendFloat64(&wkb, value: 8.0, littleEndian: true)
        appendFloat64(&wkb, value: 8.0, littleEndian: true)
        appendFloat64(&wkb, value: 2.0, littleEndian: true)
        appendFloat64(&wkb, value: 2.0, littleEndian: true)

        let data = buildMySQLGeometry(wkb: wkb)
        let result = GeometryWKBParser.parse(data)
        #expect(result == "POLYGON((0.0 0.0, 10.0 0.0, 10.0 10.0, 0.0 0.0), (2.0 2.0, 8.0 2.0, 8.0 8.0, 2.0 2.0))")
    }

    // MARK: - MULTIPOINT Parsing

    @Test("Valid WKB MULTIPOINT with 2 points")
    func multiPoint2Points() {
        var wkb: [UInt8] = [0x01]
        appendUInt32(&wkb, value: 4, littleEndian: true)
        appendUInt32(&wkb, value: 2, littleEndian: true)
        wkb.append(contentsOf: wkbPoint(x: 1.0, y: 2.0))
        wkb.append(contentsOf: wkbPoint(x: 3.0, y: 4.0))

        let data = buildMySQLGeometry(wkb: wkb)
        let result = GeometryWKBParser.parse(data)
        #expect(result == "MULTIPOINT(1.0 2.0, 3.0 4.0)")
    }

    // MARK: - Edge Cases

    @Test("Empty data returns empty string")
    func emptyData() {
        let data = Data()
        let result = GeometryWKBParser.parse(data)
        #expect(result == "")
    }

    @Test("Buffer too short returns hex fallback")
    func tooShortBuffer() {
        let data = Data([0x00, 0x00, 0x00, 0x00, 0x01, 0x01])
        let result = GeometryWKBParser.parse(data)
        #expect(result.hasPrefix("0x"))
    }

    @Test("Unknown WKB type code returns hex fallback")
    func unknownTypeCode() {
        var wkb: [UInt8] = [0x01]
        appendUInt32(&wkb, value: 99, littleEndian: true)

        let data = buildMySQLGeometry(wkb: wkb)
        let result = GeometryWKBParser.parse(data)
        #expect(result.hasPrefix("0x"))
    }
}
