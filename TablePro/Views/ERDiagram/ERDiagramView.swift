import AppKit
import os
import SwiftUI
import UniformTypeIdentifiers

struct ERDiagramView: View {
    @Bindable var viewModel: ERDiagramViewModel
    @State private var selectedNodeId: UUID?
    @State private var draggingNodeId: UUID?
    @State private var dragStart: CGPoint?
    @State private var dragNodeStart: CGPoint?
    @State private var canvasOffset: CGPoint = .zero
    @State private var panStart: CGPoint?
    @State private var scrollMonitor: Any?

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
        GeometryReader { _ in
            diagramCanvas
                .scaleEffect(viewModel.magnification, anchor: .topLeading)
                .offset(x: canvasOffset.x, y: canvasOffset.y)
                .clipped()
                .gesture(combinedGesture)
        }
        .onAppear {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
                canvasOffset = CGPoint(
                    x: canvasOffset.x + event.scrollingDeltaX * multiplier,
                    y: canvasOffset.y + event.scrollingDeltaY * multiplier
                )
                return event
            }
        }
        .onDisappear {
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
        }
    }

    // MARK: - Single Canvas (draws everything)

    private var diagramCanvas: some View {
        Canvas { context, _ in
            let nodeRects = buildNodeRects()

            // Draw edges
            ERDiagramEdgeRenderer.drawEdges(
                context: context,
                edges: viewModel.graph.edges,
                nodeRects: nodeRects,
                nodeIndex: viewModel.graph.nodeIndex
            )

            // Draw nodes
            for node in viewModel.graph.nodes {
                guard let rect = nodeRects[node.id] else { continue }
                drawTableNode(context: &context, node: node, rect: rect)
            }
        }
        .frame(width: viewModel.canvasSize.width, height: viewModel.canvasSize.height)
    }

    // MARK: - Node Drawing (imperative)

    private func drawTableNode(context: inout GraphicsContext, node: ERTableNode, rect: CGRect) {
        let isSelected = selectedNodeId == node.id
        let cornerRadius: CGFloat = 6
        let roundedRect = RoundedRectangle(cornerRadius: cornerRadius)
        let path = Path(roundedRect: rect, cornerRadius: cornerRadius)

        // Background
        context.fill(path, with: .color(Color(nsColor: .controlBackgroundColor)))

        // Border
        let borderColor = isSelected ? Color.accentColor : Color(nsColor: .separatorColor)
        context.stroke(path, with: .color(borderColor), lineWidth: isSelected ? 2 : 1)

        // Header background
        let headerHeight: CGFloat = ERDiagramLayout.headerHeight
        let headerRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: headerHeight)
        let headerPath = Path { p in
            p.addRoundedRect(
                in: headerRect,
                cornerRadii: RectangleCornerRadii(topLeading: cornerRadius, topTrailing: cornerRadius)
            )
        }
        context.fill(headerPath, with: .color(Color.accentColor.opacity(0.08)))

        // Header text
        let headerText = Text(node.tableName)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
        context.draw(
            context.resolve(headerText),
            at: CGPoint(x: rect.minX + 28, y: rect.minY + headerHeight / 2),
            anchor: .leading
        )

        // Table icon
        let iconText = Text(Image(systemName: "tablecells"))
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        context.draw(
            context.resolve(iconText),
            at: CGPoint(x: rect.minX + 10, y: rect.minY + headerHeight / 2),
            anchor: .leading
        )

        // Header divider
        let dividerY = rect.minY + headerHeight
        var dividerPath = Path()
        dividerPath.move(to: CGPoint(x: rect.minX, y: dividerY))
        dividerPath.addLine(to: CGPoint(x: rect.maxX, y: dividerY))
        context.stroke(dividerPath, with: .color(Color(nsColor: .separatorColor)), lineWidth: 0.5)

        // Column rows
        let rowHeight = ERDiagramLayout.columnRowHeight
        for (idx, col) in node.displayColumns.enumerated() {
            let rowY = dividerY + CGFloat(idx) * rowHeight + rowHeight / 2

            // PK/FK badge
            if col.isPrimaryKey {
                let badge = Text(Image(systemName: "key.fill")).font(.system(size: 8)).foregroundStyle(.yellow)
                context.draw(context.resolve(badge), at: CGPoint(x: rect.minX + 14, y: rowY), anchor: .center)
            } else if col.isForeignKey {
                let badge = Text(Image(systemName: "link")).font(.system(size: 8)).foregroundStyle(.blue)
                context.draw(context.resolve(badge), at: CGPoint(x: rect.minX + 14, y: rowY), anchor: .center)
            }

            // Column name
            let nameText = Text(col.name).font(.system(size: 11, design: .monospaced))
            context.draw(
                context.resolve(nameText),
                at: CGPoint(x: rect.minX + 24, y: rowY),
                anchor: .leading
            )

            // Column type
            let typeText = Text(col.dataType)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            context.draw(
                context.resolve(typeText),
                at: CGPoint(x: rect.maxX - 8, y: rowY),
                anchor: .trailing
            )
        }
    }

    // MARK: - Hit Testing

    private func nodeAt(point: CGPoint) -> UUID? {
        let canvasPoint = CGPoint(
            x: (point.x - canvasOffset.x) / viewModel.magnification,
            y: (point.y - canvasOffset.y) / viewModel.magnification
        )
        let rects = buildNodeRects()
        for (id, rect) in rects where rect.contains(canvasPoint) {
            return id
        }
        return nil
    }

    private func buildNodeRects() -> [UUID: CGRect] {
        Dictionary(uniqueKeysWithValues: viewModel.graph.nodes.map { ($0.id, viewModel.nodeRect(for: $0.id)) })
    }

    // MARK: - Combined Gesture (pan + node drag)

    private var combinedGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStart == nil {
                    // First event — determine if dragging a node or panning
                    let hitNode = nodeAt(point: value.startLocation)
                    draggingNodeId = hitNode
                    dragStart = value.startLocation

                    if let nodeId = hitNode {
                        dragNodeStart = viewModel.position(for: nodeId)
                    } else {
                        panStart = canvasOffset
                    }
                }

                if let nodeId = draggingNodeId, let nodeStart = dragNodeStart {
                    // Dragging a node
                    let scaledDelta = CGSize(
                        width: value.translation.width / viewModel.magnification,
                        height: value.translation.height / viewModel.magnification
                    )
                    viewModel.setPositionOverride(
                        nodeId: nodeId,
                        position: CGPoint(x: nodeStart.x + scaledDelta.width, y: nodeStart.y + scaledDelta.height)
                    )
                } else if let start = panStart {
                    // Panning the canvas
                    canvasOffset = CGPoint(
                        x: start.x + value.translation.width,
                        y: start.y + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                if draggingNodeId != nil {
                    viewModel.persistPositions()
                }
                draggingNodeId = nil
                dragStart = nil
                dragNodeStart = nil
                panStart = nil
            }
            .simultaneously(with: TapGesture().onEnded {})
    }

    // MARK: - Tap (via click location)

    // Note: Tap for selection is handled via onTapGesture on the GeometryReader
    // because Canvas doesn't support per-element tap

    // MARK: - Export

    private func exportDiagram() {
        let exportView = diagramCanvas
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
