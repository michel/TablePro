//
//  DateExtensionsTests.swift
//  TableProTests
//
//  Tests for Date extension methods
//

import Foundation
import Testing

@testable import TablePro

@Suite("Date Extensions")
struct DateExtensionsTests {
    @Test("Just now (seconds ago)")
    func testJustNow() {
        let date = Date().addingTimeInterval(-30) // 30 seconds ago

        let result = date.timeAgoDisplay()

        #expect(result == String(localized: "just now"))
    }

    @Test("1 minute ago")
    func testOneMinuteAgo() {
        let date = Date().addingTimeInterval(-60) // 60 seconds = 1 minute ago

        let result = date.timeAgoDisplay()

        #expect(result == String(localized: "1 minute ago"))
    }

    @Test("Multiple minutes ago")
    func testMultipleMinutesAgo() {
        let date = Date().addingTimeInterval(-30 * 60) // 30 minutes ago

        let result = date.timeAgoDisplay()

        #expect(result == String(localized: "30 minutes ago"))
    }

    @Test("1 hour ago")
    func testOneHourAgo() {
        let date = Date().addingTimeInterval(-60 * 60) // 1 hour ago

        let result = date.timeAgoDisplay()

        #expect(result == String(localized: "1 hour ago"))
    }

    @Test("Multiple hours ago")
    func testMultipleHoursAgo() {
        let date = Date().addingTimeInterval(-5 * 60 * 60) // 5 hours ago

        let result = date.timeAgoDisplay()

        #expect(result == String(localized: "5 hours ago"))
    }

    @Test("Yesterday (1 day)")
    func testYesterday() {
        let date = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours = 1 day ago

        let result = date.timeAgoDisplay()

        #expect(result == String(localized: "yesterday"))
    }

    @Test("Multiple days ago")
    func testMultipleDaysAgo() {
        let date = Date().addingTimeInterval(-3 * 24 * 60 * 60) // 3 days ago

        let result = date.timeAgoDisplay()

        #expect(result == String(localized: "3 days ago"))
    }

    @Test("1 week ago")
    func testOneWeekAgo() {
        let date = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7 days = 1 week ago

        let result = date.timeAgoDisplay()

        #expect(result == String(localized: "1 week ago"))
    }

    @Test("1 month ago")
    func testOneMonthAgo() {
        let date = Date().addingTimeInterval(-35 * 24 * 60 * 60) // ~35 days = 1 month ago

        let result = date.timeAgoDisplay()

        #expect(result == String(localized: "1 month ago"))
    }

    @Test("1 year ago")
    func testOneYearAgo() {
        let date = Date().addingTimeInterval(-400 * 24 * 60 * 60) // ~400 days = 1 year ago

        let result = date.timeAgoDisplay()

        #expect(result == String(localized: "1 year ago"))
    }
}
