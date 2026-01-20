//
//  DateFormattingService.swift
//  OpenTable
//
//  Centralized date formatting service that respects user settings.
//  Thread-safe singleton that formats dates according to DataGridSettings.dateFormat.
//

import Foundation

/// Centralized date formatting service that respects user settings
@MainActor
final class DateFormattingService {
    static let shared = DateFormattingService()

    // MARK: - Properties

    /// Cached formatter for current user-selected format
    private var formatter: DateFormatter

    /// Current date format option
    private(set) var currentFormat: DateFormatOption

    /// Parsers for common database date formats (ISO 8601, MySQL, PostgreSQL, SQLite)
    private let parsers: [DateFormatter]

    // MARK: - Initialization

    private init() {
        // Initialize with default format (ISO 8601)
        // Will be updated by AppSettingsManager after it completes initialization
        self.currentFormat = .iso8601
        self.formatter = Self.createFormatter(for: .iso8601)
        self.parsers = Self.createParsers()
    }

    // MARK: - Public Methods

    /// Update the date format (called by AppSettingsManager when settings change)
    func updateFormat(_ format: DateFormatOption) {
        guard format != currentFormat else { return }
        currentFormat = format
        formatter = Self.createFormatter(for: format)
    }

    /// Format a date using current user settings
    /// - Parameter date: The date to format
    /// - Returns: Formatted date string
    func format(_ date: Date) -> String {
        formatter.string(from: date)
    }

    /// Format a string date value (parse then format)
    /// - Parameter dateString: Date string from database (ISO 8601, MySQL timestamp, etc.)
    /// - Returns: Formatted date string, or nil if unparseable
    func format(dateString: String) -> String? {
        // Try parsing with each parser
        for parser in parsers {
            if let date = parser.date(from: dateString) {
                return format(date)
            }
        }

        // Could not parse - return nil to signal caller to use original string
        return nil
    }

    // MARK: - Private Helper Methods

    /// Create formatter for a specific format option
    /// - Parameter option: The date format option
    /// - Returns: Configured DateFormatter
    private static func createFormatter(for option: DateFormatOption) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = option.formatString
        formatter.locale = Locale.current  // Use user's locale for localized formatting
        formatter.timeZone = TimeZone.current  // Use user's timezone
        return formatter
    }

    /// Create parsers for common database date formats
    /// Parsers are tried in order until one successfully parses the input
    /// - Returns: Array of DateFormatters for parsing
    private static func createParsers() -> [DateFormatter] {
        let formats = [
            "yyyy-MM-dd HH:mm:ss",      // MySQL/PostgreSQL timestamp (most common)
            "yyyy-MM-dd'T'HH:mm:ss",    // ISO 8601 (no timezone)
            "yyyy-MM-dd'T'HH:mm:ssZ",   // ISO 8601 with timezone
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ", // ISO 8601 with milliseconds and timezone
            "yyyy-MM-dd",               // Date only (MySQL DATE, PostgreSQL DATE)
            "HH:mm:ss",                 // Time only (MySQL TIME)
        ]

        return formats.map { format in
            let parser = DateFormatter()
            parser.dateFormat = format
            // Use POSIX locale for parsing to avoid localization issues
            parser.locale = Locale(identifier: "en_US_POSIX")
            // Parse as UTC by default (database values are typically UTC)
            parser.timeZone = TimeZone(secondsFromGMT: 0)
            return parser
        }
    }
}
