import Foundation

/// Sugiyama-style layered layout for ER diagrams.
/// Produces node center positions from a graph of tables and FK edges.
enum ERDiagramLayout {
    static let nodeWidth: CGFloat = 220
    static let horizontalGap: CGFloat = 60
    static let verticalGap: CGFloat = 40
    static let headerHeight: CGFloat = 36
    static let columnRowHeight: CGFloat = 22

    static func compute(
        graph: ERDiagramGraph,
        nodeHeights: [UUID: CGFloat]? = nil
    ) -> [UUID: CGPoint] {
        guard !graph.nodes.isEmpty else { return [:] }

        let adjacency = buildAdjacency(graph: graph)
        let dagEdges = breakCycles(adjacency: adjacency, nodeIds: graph.nodes.map(\.id))
        let layers = assignLayers(dagEdges: dagEdges, nodeIds: graph.nodes.map(\.id), graph: graph)
        let orderedLayers = minimizeCrossings(layers: layers, dagEdges: dagEdges)
        return assignCoordinates(orderedLayers: orderedLayers, graph: graph, nodeHeights: nodeHeights)
    }

    static func estimateHeight(columnCount: Int) -> CGFloat {
        headerHeight + CGFloat(max(columnCount, 1)) * columnRowHeight
    }

    // MARK: - Adjacency

    private static func buildAdjacency(graph: ERDiagramGraph) -> [UUID: [UUID]] {
        var adj: [UUID: [UUID]] = [:]
        for node in graph.nodes {
            adj[node.id] = []
        }
        for edge in graph.edges {
            guard let fromId = graph.nodeIndex[edge.fromTable],
                  let toId = graph.nodeIndex[edge.toTable]
            else { continue }
            // FK owner → referenced table (child → parent in ER terms)
            adj[fromId, default: []].append(toId)
        }
        return adj
    }

    // MARK: - Cycle Breaking (DFS)

    private static func breakCycles(adjacency: [UUID: [UUID]], nodeIds: [UUID]) -> [UUID: [UUID]] {
        var visited: Set<UUID> = []
        var onStack: Set<UUID> = []
        var dag = adjacency
        var backEdges: [(UUID, UUID)] = []

        func dfs(_ node: UUID) {
            visited.insert(node)
            onStack.insert(node)
            for neighbor in adjacency[node] ?? [] {
                if onStack.contains(neighbor) {
                    backEdges.append((node, neighbor))
                } else if !visited.contains(neighbor) {
                    dfs(neighbor)
                }
            }
            onStack.remove(node)
        }

        for node in nodeIds where !visited.contains(node) {
            dfs(node)
        }

        for (from, to) in backEdges {
            dag[from]?.removeAll { $0 == to }
        }

        return dag
    }

    // MARK: - Layer Assignment (Longest Path)

    private static func assignLayers(
        dagEdges: [UUID: [UUID]],
        nodeIds: [UUID],
        graph: ERDiagramGraph
    ) -> [[UUID]] {
        // Build reverse adjacency (incoming edges)
        var inDegree: [UUID: Int] = [:]
        for id in nodeIds { inDegree[id] = 0 }
        for (_, neighbors) in dagEdges {
            for n in neighbors { inDegree[n, default: 0] += 1 }
        }

        // Topological sort via Kahn's algorithm
        var queue = nodeIds.filter { (inDegree[$0] ?? 0) == 0 }
        var layerAssignment: [UUID: Int] = [:]
        for id in queue { layerAssignment[id] = 0 }

        var idx = 0
        while idx < queue.count {
            let node = queue[idx]
            idx += 1
            let currentLayer = layerAssignment[node] ?? 0
            for neighbor in dagEdges[node] ?? [] {
                let newLayer = currentLayer + 1
                if newLayer > (layerAssignment[neighbor] ?? 0) {
                    layerAssignment[neighbor] = newLayer
                }
                inDegree[neighbor] = (inDegree[neighbor] ?? 1) - 1
                if inDegree[neighbor] == 0 {
                    queue.append(neighbor)
                }
            }
        }

        // Assign any unvisited nodes (disconnected) to layer 0
        for id in nodeIds where layerAssignment[id] == nil {
            layerAssignment[id] = 0
        }

        // Group by layer
        var layers: [Int: [UUID]] = [:]
        for (id, layer) in layerAssignment {
            layers[layer, default: []].append(id)
        }

        let maxLayer = layers.keys.max() ?? 0
        return (0...maxLayer).map { layers[$0] ?? [] }
    }

    // MARK: - Crossing Minimization (Barycentric)

    private static func minimizeCrossings(layers: [[UUID]], dagEdges: [UUID: [UUID]]) -> [[UUID]] {
        guard layers.count > 1 else { return layers }

        // Build reverse edges for barycenter computation
        var reverseEdges: [UUID: [UUID]] = [:]
        for (from, neighbors) in dagEdges {
            for to in neighbors {
                reverseEdges[to, default: []].append(from)
            }
        }

        var result = layers

        // One top-down sweep
        for layerIdx in 1..<result.count {
            let upperLayer = result[layerIdx - 1]
            let upperPositions: [UUID: Int] = Dictionary(
                uniqueKeysWithValues: upperLayer.enumerated().map { ($1, $0) }
            )

            var barycenters: [UUID: Double] = [:]
            for node in result[layerIdx] {
                let neighbors = reverseEdges[node] ?? []
                let positions = neighbors.compactMap { upperPositions[$0] }
                if !positions.isEmpty {
                    barycenters[node] = Double(positions.reduce(0, +)) / Double(positions.count)
                }
            }

            result[layerIdx].sort { a, b in
                (barycenters[a] ?? Double.infinity) < (barycenters[b] ?? Double.infinity)
            }
        }

        return result
    }

    // MARK: - Coordinate Assignment

    private static func assignCoordinates(
        orderedLayers: [[UUID]],
        graph: ERDiagramGraph,
        nodeHeights: [UUID: CGFloat]?
    ) -> [UUID: CGPoint] {
        var positions: [UUID: CGPoint] = [:]
        let nodeColumnCounts: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.displayColumns.count) }
        )

        var currentX: CGFloat = nodeWidth / 2 + 40

        for layer in orderedLayers {
            var currentY: CGFloat = 40
            var maxWidth: CGFloat = 0

            for nodeId in layer {
                let colCount = nodeColumnCounts[nodeId] ?? 1
                let height = nodeHeights?[nodeId] ?? estimateHeight(columnCount: colCount)

                positions[nodeId] = CGPoint(x: currentX, y: currentY + height / 2)
                currentY += height + verticalGap
                maxWidth = max(maxWidth, nodeWidth)
            }

            currentX += maxWidth + horizontalGap
        }

        return positions
    }
}
