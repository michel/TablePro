import SwiftUI

/// Renders FK edges with crow's foot notation on a Canvas GraphicsContext.
enum ERDiagramEdgeRenderer {
    static func drawEdges(
        context: GraphicsContext,
        edges: [EREdge],
        nodeRects: [UUID: CGRect],
        nodeIndex: [String: UUID]
    ) {
        let strokeColor = Color.secondary.opacity(0.5)
        let strokeStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)

        for edge in edges {
            guard let fromId = nodeIndex[edge.fromTable],
                  let toId = nodeIndex[edge.toTable],
                  let fromRect = nodeRects[fromId],
                  let toRect = nodeRects[toId]
            else { continue }

            let (srcPort, dstPort) = computePorts(from: fromRect, to: toRect)
            let path = bezierPath(from: srcPort, to: dstPort)

            context.stroke(path, with: .color(strokeColor), style: strokeStyle)
            drawCrowFoot(context: context, at: srcPort, toward: dstPort, color: strokeColor)
            drawOneBar(context: context, at: dstPort, toward: srcPort, color: strokeColor)
        }
    }

    // MARK: - Port Selection

    private static func computePorts(from fromRect: CGRect, to toRect: CGRect) -> (CGPoint, CGPoint) {
        let fromCenter = CGPoint(x: fromRect.midX, y: fromRect.midY)
        let toCenter = CGPoint(x: toRect.midX, y: toRect.midY)

        let srcPort: CGPoint
        let dstPort: CGPoint

        if fromCenter.x < toCenter.x {
            srcPort = CGPoint(x: fromRect.maxX, y: fromRect.midY)
            dstPort = CGPoint(x: toRect.minX, y: toRect.midY)
        } else if fromCenter.x > toCenter.x {
            srcPort = CGPoint(x: fromRect.minX, y: fromRect.midY)
            dstPort = CGPoint(x: toRect.maxX, y: toRect.midY)
        } else {
            if fromCenter.y < toCenter.y {
                srcPort = CGPoint(x: fromRect.midX, y: fromRect.maxY)
                dstPort = CGPoint(x: toRect.midX, y: toRect.minY)
            } else {
                srcPort = CGPoint(x: fromRect.midX, y: fromRect.minY)
                dstPort = CGPoint(x: toRect.midX, y: toRect.maxY)
            }
        }

        return (srcPort, dstPort)
    }

    // MARK: - Bezier Path

    private static func bezierPath(from src: CGPoint, to dst: CGPoint) -> Path {
        let dx = abs(dst.x - src.x) * 0.4
        let dy = abs(dst.y - src.y) * 0.4

        let isHorizontal = abs(dst.x - src.x) > abs(dst.y - src.y)

        let cp1: CGPoint
        let cp2: CGPoint

        if isHorizontal {
            cp1 = CGPoint(x: src.x + (dst.x > src.x ? dx : -dx), y: src.y)
            cp2 = CGPoint(x: dst.x + (src.x > dst.x ? dx : -dx), y: dst.y)
        } else {
            cp1 = CGPoint(x: src.x, y: src.y + (dst.y > src.y ? dy : -dy))
            cp2 = CGPoint(x: dst.x, y: dst.y + (src.y > dst.y ? dy : -dy))
        }

        var path = Path()
        path.move(to: src)
        path.addCurve(to: dst, control1: cp1, control2: cp2)
        return path
    }

    // MARK: - Crow's Foot (Many Side)

    private static func drawCrowFoot(context: GraphicsContext, at point: CGPoint, toward target: CGPoint, color: Color) {
        let length: CGFloat = 10
        let spread: CGFloat = 6
        let angle = atan2(target.y - point.y, target.x - point.x)

        let tipX = point.x + length * cos(angle)
        let tipY = point.y + length * sin(angle)

        let perpAngle = angle + .pi / 2

        // Three prongs from the tip back to spread points
        let top = CGPoint(x: point.x + spread * cos(perpAngle), y: point.y + spread * sin(perpAngle))
        let bottom = CGPoint(x: point.x - spread * cos(perpAngle), y: point.y - spread * sin(perpAngle))

        var path = Path()
        path.move(to: CGPoint(x: tipX, y: tipY))
        path.addLine(to: top)
        path.move(to: CGPoint(x: tipX, y: tipY))
        path.addLine(to: point)
        path.move(to: CGPoint(x: tipX, y: tipY))
        path.addLine(to: bottom)

        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }

    // MARK: - One Bar (PK Side)

    private static func drawOneBar(context: GraphicsContext, at point: CGPoint, toward target: CGPoint, color: Color) {
        let barWidth: CGFloat = 8
        let angle = atan2(target.y - point.y, target.x - point.x)
        let perpAngle = angle + .pi / 2

        let top = CGPoint(x: point.x + barWidth * cos(perpAngle), y: point.y + barWidth * sin(perpAngle))
        let bottom = CGPoint(x: point.x - barWidth * cos(perpAngle), y: point.y - barWidth * sin(perpAngle))

        var path = Path()
        path.move(to: top)
        path.addLine(to: bottom)

        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }
}
