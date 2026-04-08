//
//  QueryPlan.swift
//  TablePro
//
//  Data model for parsed EXPLAIN query plans.
//

import Foundation

/// A single node in an EXPLAIN query plan tree.
struct QueryPlanNode: Identifiable {
    let id = UUID()
    let operation: String
    let relation: String?
    let schema: String?
    let alias: String?
    let estimatedStartupCost: Double?
    let estimatedTotalCost: Double?
    let estimatedRows: Int?
    let estimatedWidth: Int?
    let actualStartupTime: Double?
    let actualTotalTime: Double?
    let actualRows: Int?
    let actualLoops: Int?
    let properties: [String: String]
    var children: [QueryPlanNode]

    /// Fraction of total plan cost (0.0-1.0), set after tree is built.
    var costFraction: Double = 0

    /// Exclusive cost (this node only, excluding children).
    var exclusiveCost: Double {
        let childCost = children.reduce(0.0) { $0 + ($1.estimatedTotalCost ?? 0) }
        return max(0, (estimatedTotalCost ?? 0) - childCost)
    }
}

/// A parsed EXPLAIN query plan.
struct QueryPlan {
    var rootNode: QueryPlanNode
    let planningTime: Double?
    let executionTime: Double?
    let rawText: String

    /// Compute cost fractions relative to root total cost.
    mutating func computeCostFractions() {
        let totalCost = rootNode.estimatedTotalCost ?? 1
        guard totalCost > 0 else { return }
        assignFractions(node: &rootNode, totalCost: totalCost)
    }

    private func assignFractions(node: inout QueryPlanNode, totalCost: Double) {
        node.costFraction = node.exclusiveCost / totalCost
        for i in node.children.indices {
            assignFractions(node: &node.children[i], totalCost: totalCost)
        }
    }
}
