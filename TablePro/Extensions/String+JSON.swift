//
//  String+JSON.swift
//  TablePro
//
//  JSON formatting utilities for string values.
//

import Foundation

extension String {
    /// Returns a pretty-printed version of this string if it contains valid JSON, or nil otherwise.
    func prettyPrintedAsJson() -> String? {
        guard let data = data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(
                  withJSONObject: jsonObject,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return prettyString
    }
}
