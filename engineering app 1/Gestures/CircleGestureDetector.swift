////
//  CircleGestureDetector.swift
//  Tolerance
//

import Foundation
import CoreGraphics
import PencilKit

struct CircleGestureResult {
    let loopStrokeIndex: Int
    let contentRect: CGRect
    let loopRect: CGRect
    let hasEnclosedInk: Bool
}

enum CircleGestureDetector {

    static func detect(in drawing: PKDrawing) -> CircleGestureResult? {
        guard let lastIndex = drawing.strokes.indices.last else { return nil }
        let loop = drawing.strokes[lastIndex]
        let pts = points(of: loop)
        guard pts.count >= 10 else { return nil } // Require enough points for a real loop

        let loopRect = boundingBox(of: pts)
        let diagonal = hypot(loopRect.width, loopRect.height)

        // Ignore tiny marks (dots on i's, decimal points, short dashes).
        guard diagonal >= 50 else { return nil }

        // Start and end of stroke must close tightly (within 25% of bounding diagonal).
        guard distance(pts.first!, pts.last!) <= 0.25 * diagonal else { return nil }

        // Must turn a full 360 degrees (2π).
        let turning = totalTurning(pts)
        guard abs(turning) >= 1.8 * .pi else { return nil }

        // Reject long thin scribbles or lines.
        let longSide = max(loopRect.width, loopRect.height)
        let shortSide = min(loopRect.width, loopRect.height)
        guard shortSide >= 0.25 * longSide else { return nil }

        // Find other strokes enclosed inside the loop using actual polygon hit testing.
        var enclosed = CGRect.null
        var found = false

        for (i, stroke) in drawing.strokes.enumerated() where i != lastIndex {
            let bounds = stroke.renderBounds
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            
            // First fast-check bounding box inset, then verify point lies inside polygon path
            if loopRect.contains(center) && containsPoint(center, inPolygon: pts) {
                enclosed = enclosed.union(bounds)
                found = true
            }
        }

        // ONLY trigger if we actually enclosed previous ink!
        guard found else { return nil }

        return CircleGestureResult(
            loopStrokeIndex: lastIndex,
            contentRect: enclosed,
            loopRect: loopRect,
            hasEnclosedInk: true
        )
    }

    static func removingLoop(_ result: CircleGestureResult, from drawing: PKDrawing) -> PKDrawing {
        var strokes = drawing.strokes
        guard strokes.indices.contains(result.loopStrokeIndex) else { return drawing }
        strokes.remove(at: result.loopStrokeIndex)
        return PKDrawing(strokes: strokes)
    }

    // MARK: - Geometry & Ray-Casting Helpers

    private static func points(of stroke: PKStroke) -> [CGPoint] {
        let transform = stroke.transform
        return stroke.path.map { $0.location.applying(transform) }
    }

    private static func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func totalTurning(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var total: CGFloat = 0
        var previousAngle = atan2(points[1].y - points[0].y, points[1].x - points[0].x)
        for i in 1..<(points.count - 1) {
            let angle = atan2(points[i + 1].y - points[i].y, points[i + 1].x - points[i].x)
            var delta = angle - previousAngle
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            total += delta
            previousAngle = angle
        }
        return total
    }

    /// Ray-casting algorithm to determine if a point is inside a polygon
    private static func containsPoint(_ point: CGPoint, inPolygon polygon: [CGPoint]) -> Bool {
        var isInside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            if (polygon[i].y > point.y) != (polygon[j].y > point.y) &&
                (point.x < (polygon[j].x - polygon[i].x) * (point.y - polygon[i].y) / (polygon[j].y - polygon[i].y) + polygon[i].x) {
                isInside.toggle()
            }
            j = i
        }
        return isInside
    }
}
