//
//  CircleGestureDetector.swift
//  Tolerance
//
//  Phase 4: decides whether the most recently drawn stroke is a "circle
//  gesture" — a roughly closed loop that encloses other ink — as opposed to
//  ordinary writing or a doodle. This is a heuristic, not exact shape
//  recognition, per the v1 spec.
//
//  Only PencilKit's data types are used here (PKDrawing/PKStroke/PKStrokePath),
//  which are available on all platforms, so this file needs no platform guard.
//

import Foundation
import CoreGraphics
import PencilKit

/// The outcome of a successful circle-gesture detection. All rectangles are in
/// the drawing's coordinate space (the same space as `PKStroke.renderBounds`).
struct CircleGestureResult {
    /// Index of the loop stroke within `drawing.strokes`, so the caller can
    /// remove it (the loop is a transient gesture, never committed ink).
    let loopStrokeIndex: Int

    /// Bounding box of the ink enclosed by the loop (or the loop itself if the
    /// loop encloses no other strokes).
    let contentRect: CGRect

    /// Bounding box of the loop stroke.
    let loopRect: CGRect

    /// Whether the loop actually encloses other strokes (content to analyze).
    let hasEnclosedInk: Bool
}

enum CircleGestureDetector {

    /// Analyze the drawing's most recent stroke. Returns a result if it looks
    /// like a closed loop around content, otherwise `nil`.
    static func detect(in drawing: PKDrawing) -> CircleGestureResult? {
        guard let lastIndex = drawing.strokes.indices.last else { return nil }
        let loop = drawing.strokes[lastIndex]
        let pts = points(of: loop)
        guard pts.count >= 6 else { return nil }

        let loopRect = boundingBox(of: pts)
        let diagonal = hypot(loopRect.width, loopRect.height)

        // Ignore tiny marks (dots on i's, decimal points, short dashes).
        guard diagonal >= 40 else { return nil }

        // The path must return close to where it started (a closed loop).
        guard distance(pts.first!, pts.last!) <= 0.4 * diagonal else { return nil }

        // A real loop turns through roughly a full revolution (2π). Requiring
        // most of a revolution rejects back-and-forth scribbles and check marks.
        guard abs(totalTurning(pts)) >= 1.6 * .pi else { return nil }

        // Reject very thin shapes (e.g. an underline that loops back).
        let longSide = max(loopRect.width, loopRect.height)
        let shortSide = min(loopRect.width, loopRect.height)
        guard shortSide >= 0.15 * longSide else { return nil }

        // Find other strokes whose center falls inside the loop — the content
        // the user is circling.
        let inset = loopRect.insetBy(dx: loopRect.width * 0.04, dy: loopRect.height * 0.04)
        var enclosed = CGRect.null
        var found = false
        for (i, stroke) in drawing.strokes.enumerated() where i != lastIndex {
            let bounds = stroke.renderBounds
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            if inset.contains(center) {
                enclosed = enclosed.union(bounds)
                found = true
            }
        }

        return CircleGestureResult(
            loopStrokeIndex: lastIndex,
            contentRect: found ? enclosed : loopRect,
            loopRect: loopRect,
            hasEnclosedInk: found
        )
    }

    /// Returns a copy of `drawing` with the loop stroke removed, so the gesture
    /// is never saved as permanent ink.
    static func removingLoop(_ result: CircleGestureResult, from drawing: PKDrawing) -> PKDrawing {
        var strokes = drawing.strokes
        guard strokes.indices.contains(result.loopStrokeIndex) else { return drawing }
        strokes.remove(at: result.loopStrokeIndex)
        return PKDrawing(strokes: strokes)
    }

    // MARK: - Geometry helpers

    /// The control points of a stroke, mapped into drawing coordinates.
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

    /// Sum of signed heading changes along the path. A full loop totals about
    /// ±2π; open shapes total much less.
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
}
