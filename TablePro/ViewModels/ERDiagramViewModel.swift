import CoreGraphics
import Foundation
import os
import Observation

@MainActor
@Observable
final class ERDiagramViewModel {
    private static let logger = Logger(subsystem: "com.TablePro", category: "ERDiagram")

    // MARK: - Configuration

    let connectionId: UUID
    let schemaKey: String

    // MARK: - State

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)

        static func == (lhs: LoadState, rhs: LoadState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.loaded, .loaded): return true
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    var loadState: LoadState = .loading
    var graph: ERDiagramGraph = .empty
    var magnification: CGFloat = 1.0
    var isCompactMode = false {
        didSet { rebuildDisplayColumns() }
    }

    // MARK: - Positions

    private(set) var computedLayout: [UUID: CGPoint] = [:]
    private(set) var positionOverrides: [UUID: CGPoint] = [:]
    var nodeHeights: [UUID: CGFloat] = [:]

    // MARK: - Initialization

    init(connectionId: UUID, schemaKey: String) {
        self.connectionId = connectionId
        self.schemaKey = schemaKey
    }

    // MARK: - Loading

    func loadDiagram() async {
        loadState = .loading

        guard let driver = DatabaseManager.shared.driver(for: connectionId) else {
            loadState = .failed(String(localized: "No database connection"))
            return
        }

        do {
            async let columnsResult = driver.fetchAllColumns()
            async let fksResult = driver.fetchAllForeignKeys()
            let (allColumns, allFKs) = try await (columnsResult, fksResult)

            let builtGraph = ERDiagramGraphBuilder.build(
                allColumns: allColumns,
                allForeignKeys: allFKs
            )
            graph = builtGraph

            let layout = await Task.detached {
                ERDiagramLayout.compute(graph: builtGraph)
            }.value
            computedLayout = layout
            loadPersistedPositions()
            loadState = .loaded

            Self.logger.debug("ER diagram loaded: \(self.graph.nodes.count) tables, \(self.graph.edges.count) edges")
        } catch {
            Self.logger.error("Failed to load ER diagram: \(error.localizedDescription)")
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Position Management

    func position(for nodeId: UUID) -> CGPoint {
        positionOverrides[nodeId] ?? computedLayout[nodeId] ?? .zero
    }

    func setPositionOverride(nodeId: UUID, position: CGPoint) {
        positionOverrides[nodeId] = position
    }

    func persistPositions() {
        let namedPositions = positionOverrides.reduce(into: [String: CGPoint]()) { result, pair in
            if let node = graph.nodes.first(where: { $0.id == pair.key }) {
                result[node.tableName] = pair.value
            }
        }
        ERDiagramPositionStorage.shared.save(namedPositions, connectionId: connectionId, schemaKey: schemaKey)
    }

    func resetLayout() {
        positionOverrides.removeAll()
        computedLayout = ERDiagramLayout.compute(graph: graph, nodeHeights: nodeHeights)
        ERDiagramPositionStorage.shared.clear(connectionId: connectionId, schemaKey: schemaKey)
    }

    // MARK: - Compact Mode

    private func rebuildDisplayColumns() {
        graph.nodes = graph.nodes.map { node in
            var updated = node
            updated.displayColumns = isCompactMode
                ? node.columns.filter { $0.isPrimaryKey || $0.isForeignKey }
                : node.columns
            if updated.displayColumns.isEmpty {
                updated.displayColumns = node.columns
            }
            return updated
        }
        let currentGraph = graph
        let heights = nodeHeights
        Task {
            let layout = await Task.detached {
                ERDiagramLayout.compute(graph: currentGraph, nodeHeights: heights)
            }.value
            computedLayout = layout
        }
    }

    // MARK: - Canvas Size

    var canvasSize: CGSize {
        guard !graph.nodes.isEmpty else { return CGSize(width: 800, height: 600) }
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for node in graph.nodes {
            let pos = position(for: node.id)
            let height = nodeHeights[node.id] ?? ERDiagramLayout.estimateHeight(columnCount: node.displayColumns.count)
            maxX = max(maxX, pos.x + ERDiagramLayout.nodeWidth / 2)
            maxY = max(maxY, pos.y + height / 2)
        }
        return CGSize(width: maxX + 80, height: maxY + 80)
    }

    // MARK: - Node Rect (for edge rendering)

    func nodeRect(for nodeId: UUID) -> CGRect {
        let center = position(for: nodeId)
        let height = nodeHeights[nodeId]
            ?? ERDiagramLayout.estimateHeight(
                columnCount: graph.nodes.first { $0.id == nodeId }?.displayColumns.count ?? 1
            )
        return CGRect(
            x: center.x - ERDiagramLayout.nodeWidth / 2,
            y: center.y - height / 2,
            width: ERDiagramLayout.nodeWidth,
            height: height
        )
    }

    // MARK: - Private

    private func loadPersistedPositions() {
        let stored = ERDiagramPositionStorage.shared.load(connectionId: connectionId, schemaKey: schemaKey)
        for (tableName, point) in stored {
            if let nodeId = graph.nodeIndex[tableName] {
                positionOverrides[nodeId] = point
            }
        }
    }
}
