import AppKit
import os
import SwiftUI
import UniformTypeIdentifiers

struct ERDiagramView: View {
    @Bindable var viewModel: ERDiagramViewModel
    @State private var selectedNodeId: UUID?
    @State private var dragOffsets: [UUID: CGSize] = [:]
    @State private var dragStartPositions: [UUID: CGPoint] = [:]

    private static let logger = Logger(subsystem: "com.TablePro", category: "ERDiagramView")

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            switch viewModel.loadState {
            case .loading:
                ProgressView(String(localized: "Loading schema..."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(message)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Retry")) {
                        Task { await viewModel.loadDiagram() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded:
                diagramContent
                ERDiagramToolbar(viewModel: viewModel, onExport: exportDiagram)
            }
        }
        .task { await viewModel.loadDiagram() }
    }

    // MARK: - Diagram Content

    private var diagramContent: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                edgeCanvas
                nodeLayer
            }
            .frame(width: viewModel.canvasSize.width, height: viewModel.canvasSize.height)
            .scaleEffect(viewModel.magnification, anchor: .topLeading)
            .frame(
                width: viewModel.canvasSize.width * viewModel.magnification,
                height: viewModel.canvasSize.height * viewModel.magnification,
                alignment: .topLeading
            )
        }
    }

    // MARK: - Edge Canvas

    private var edgeCanvas: some View {
        Canvas { context, _ in
            let nodeRects = Dictionary(
                uniqueKeysWithValues: viewModel.graph.nodes.map { ($0.id, viewModel.nodeRect(for: $0.id)) }
            )
            ERDiagramEdgeRenderer.drawEdges(
                context: context,
                edges: viewModel.graph.edges,
                nodeRects: nodeRects,
                nodeIndex: viewModel.graph.nodeIndex
            )
        }
        .frame(width: viewModel.canvasSize.width, height: viewModel.canvasSize.height)
        .allowsHitTesting(false)
    }

    // MARK: - Node Layer

    private var nodeLayer: some View {
        ForEach(viewModel.graph.nodes) { node in
            ERTableNodeView(node: node, isSelected: selectedNodeId == node.id)
                .fixedSize()
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: NodeHeightPreferenceKey.self, value: [node.id: geo.size.height])
                    }
                )
                .position(nodePosition(for: node.id))
                .gesture(dragGesture(for: node.id))
                .onTapGesture { selectedNodeId = selectedNodeId == node.id ? nil : node.id }
        }
        .onPreferenceChange(NodeHeightPreferenceKey.self) { heights in
            for (id, height) in heights {
                viewModel.nodeHeights[id] = height
            }
        }
    }

    // MARK: - Drag

    private func nodePosition(for nodeId: UUID) -> CGPoint {
        let base = viewModel.position(for: nodeId)
        let offset = dragOffsets[nodeId] ?? .zero
        return CGPoint(x: base.x + offset.width, y: base.y + offset.height)
    }

    private func dragGesture(for nodeId: UUID) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartPositions[nodeId] == nil {
                    dragStartPositions[nodeId] = viewModel.position(for: nodeId)
                }
                dragOffsets[nodeId] = value.translation
            }
            .onEnded { value in
                let base = dragStartPositions[nodeId] ?? viewModel.position(for: nodeId)
                viewModel.setPositionOverride(
                    nodeId: nodeId,
                    position: CGPoint(
                        x: base.x + value.translation.width,
                        y: base.y + value.translation.height
                    )
                )
                dragOffsets[nodeId] = nil
                dragStartPositions[nodeId] = nil
                viewModel.persistPositions()
            }
    }


    // MARK: - Export

    private func exportDiagram() {
        let exportView = ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                let nodeRects = Dictionary(
                    uniqueKeysWithValues: viewModel.graph.nodes.map { ($0.id, viewModel.nodeRect(for: $0.id)) }
                )
                ERDiagramEdgeRenderer.drawEdges(
                    context: context,
                    edges: viewModel.graph.edges,
                    nodeRects: nodeRects,
                    nodeIndex: viewModel.graph.nodeIndex
                )
            }
            .frame(width: viewModel.canvasSize.width, height: viewModel.canvasSize.height)

            ForEach(viewModel.graph.nodes) { node in
                ERTableNodeView(node: node, isSelected: false)
                    .position(viewModel.position(for: node.id))
            }
        }
        .frame(width: viewModel.canvasSize.width, height: viewModel.canvasSize.height)
        .background(Color(nsColor: ThemeEngine.shared.colors.sidebar.background))

        let renderer = ImageRenderer(content: exportView)
        renderer.scale = 2.0

        guard let image = renderer.nsImage else {
            Self.logger.error("Failed to render ER diagram to image")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "er-diagram.png"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:])
            else { return }
            try? pngData.write(to: url)
        }
    }
}

// MARK: - Preference Key

private struct NodeHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
