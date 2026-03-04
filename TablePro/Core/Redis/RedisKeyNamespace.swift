//
//  RedisKeyNamespace.swift
//  TablePro
//
//  Groups Redis keys by colon-delimited namespace prefix.
//  Used by the sidebar for namespace-grouped key browsing.
//

import Foundation

/// Represents a hierarchical namespace grouping of Redis keys
struct RedisKeyNamespace: Identifiable, Hashable {
    let id: String
    let name: String
    let keyCount: Int
    let children: [RedisKeyNamespace]

    var isLeaf: Bool { children.isEmpty }

    /// SCAN pattern that matches all keys in this namespace
    var scanPattern: String { "\(id)*" }

    // MARK: - Tree Construction

    /// Build a namespace tree from a flat list of Redis keys.
    /// Keys are grouped by prefix components split on the separator (default ":").
    /// Keys without a separator go into a "(no namespace)" group.
    static func buildTree(from keys: [String], separator: String = ":") -> [RedisKeyNamespace] {
        var prefixGroups: [String: [String]] = [:]
        var ungroupedCount = 0

        for key in keys {
            if let sepRange = key.range(of: separator) {
                let prefix = String(key[key.startIndex..<sepRange.lowerBound])
                prefixGroups[prefix, default: []].append(key)
            } else {
                ungroupedCount += 1
            }
        }

        var namespaces: [RedisKeyNamespace] = []

        for prefix in prefixGroups.keys.sorted() {
            guard let groupKeys = prefixGroups[prefix] else { continue }
            let fullPrefix = prefix + separator
            let children = buildChildren(from: groupKeys, prefix: fullPrefix, separator: separator)
            namespaces.append(RedisKeyNamespace(
                id: fullPrefix,
                name: prefix,
                keyCount: groupKeys.count,
                children: children
            ))
        }

        if ungroupedCount > 0 {
            namespaces.append(RedisKeyNamespace(
                id: "",
                name: "(no namespace)",
                keyCount: ungroupedCount,
                children: []
            ))
        }

        return namespaces
    }

    /// Recursively build child namespaces from keys that share a common prefix
    private static func buildChildren(
        from keys: [String],
        prefix: String,
        separator: String
    ) -> [RedisKeyNamespace] {
        var subGroups: [String: [String]] = [:]
        var leafCount = 0

        for key in keys {
            let suffix = String(key.dropFirst(prefix.count))
            if let sepRange = suffix.range(of: separator) {
                let subPrefix = String(suffix[suffix.startIndex..<sepRange.lowerBound])
                subGroups[subPrefix, default: []].append(key)
            } else {
                leafCount += 1
            }
        }

        // Only create sub-namespaces if there are meaningful groupings
        guard !subGroups.isEmpty else { return [] }

        var children: [RedisKeyNamespace] = []

        for subPrefix in subGroups.keys.sorted() {
            guard let groupKeys = subGroups[subPrefix] else { continue }
            let fullPrefix = prefix + subPrefix + separator
            let grandchildren = buildChildren(from: groupKeys, prefix: fullPrefix, separator: separator)
            children.append(RedisKeyNamespace(
                id: fullPrefix,
                name: subPrefix,
                keyCount: groupKeys.count,
                children: grandchildren
            ))
        }

        return children
    }
}
