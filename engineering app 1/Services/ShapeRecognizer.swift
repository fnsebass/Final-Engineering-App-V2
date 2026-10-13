//
//  ShapeRecognizer.swift
//  Tolerance
//
//  Classifies a freehand point path (from the Smart Draw tool) into a
//  clean geometric shape: a straight line, an arrow, an ellipse, or a
//  straight-edged polygon (triangle, rectangle/square, or an n-gon).
//
//  Pure geometry — no PencilKit/UIKit dependency, so the classification
//  heuristics can be reasoned about (and unit-tested) independently of
//  drawing/rendering. See ShapeStrokeBuilder for turning a RecognizedShape
//  into actual ink, and SmartDrawOverlay for how a stroke is captured and
//  fed in here.
//

import Foundation
import CoreGraphics

enum RecognizedShape {
    case line(CGPoint, CGPoint)
    case arrow(CGPoint, CGPoint)
    case ellipse(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat)
    /// A straight-edged closed shape — 3 points is a triangle, 4 is a
    /// rectangle/square, 5+ is a general polygon. Already regularized
    /// (right angles enforced for 4, proportional square/circle
    /// constraining applied) by the time this is returned.
    case polygon([CGPoint])
}

enum ShapeRecognizer {

    /// Below this many raw points there isn't enough signal to classify anything.
    private static let minPoints = 6
    /// Ignore marks smaller than this (dots, decimal points, short dashes).
    private static let minDiagonal: CGFloat = 24

    static func recognize(_ rawPoints: [CGPoint]) -> RecognizedShape? {
        guard rawPoints.count >= minPoints else { return nil }
        let points = resample(rawPoints, targetSpacing: 6)
        guard points.count >= minPoints, let first = points.first, let last = points.last else { return nil }

        let bounds = boundingBox(points)
        let diagonal = hypot(bounds.width, bounds.height)
        guard diagonal >= minDiagonal else { return nil }

        let closingGap = distance(first, last)
        let isClosed = closingGap <= 0.22 * diagonal

        return isClosed ? recognizeClosed(points, diagonal: diagonal)
                         : recognizeOpen(points, diagonal: diagonal)
    }

    // MARK: - Open strokes: line or arrow

    private static func recognizeOpen(_ points: [CGPoint], diagonal: CGFloat) -> RecognizedShape? {
        let start = points.first!, end = points.last!

        if let tip = detectArrowhead(points) {
            return .arrow(start, tip)
        }

        let straightLen = distance(start, end)
        guard straightLen > 0 else { return nil }
        let maxDeviation = points.map { perpendicularDistance($0, from: start, to: end) }.max() ?? 0
        // Within ~12% of the path's own length (floor of 14pt) counts as "drawn as a line".
        guard maxDeviation <= max(14, straightLen * 0.12) else { return nil }

        return .line(start, end)
    }

    /// An arrow is typically drawn as one continuous stroke: shaft, then a
    /// sharp reversal back through the tip to lay down one side of the
    /// arrowhead, then another reversal for the other side. Heuristic: walk
    /// backward from the end looking for a point where the path sharply
    /// folds back toward a point it already passed near — the fold-back
    /// point is the arrow's tip.
    private static func detectArrowhead(_ points: [CGPoint]) -> CGPoint? {
        guard points.count >= 10 else { return nil }
        let n = points.count
        // Only look within the last third of the stroke for the tell-tale
        // sharp direction reversal that marks the start of an arrowhead.
        let searchStart = max(1, n - n / 3)

        for i in stride(from: n - 2, through: searchStart, by: -1) {
            let v1 = CGVector(dx: points[i].x - points[i - 1].x, dy: points[i].y - points[i - 1].y)
            let v2 = CGVector(dx: points[i + 1].x - points[i].x, dy: points[i + 1].y - points[i].y)
            let angle = angleBetween(v1, v2)
            // A sharp fold (> ~100°) this late in the stroke, with real
            // distance still covered afterward, reads as an arrowhead start.
            if abs(angle) > (100 * .pi / 180) {
                let remaining = pathLength(Array(points[i...]))
                let shaftLength = pathLength(Array(points[0...i]))
                if remaining > 8, remaining < shaftLength * 0.6 {
                    return points[i]
                }
            }
        }
        return nil
    }

    // MARK: - Closed shapes: ellipse or straight-edged polygon

    private static func recognizeClosed(_ points: [CGPoint], diagonal: CGFloat) -> RecognizedShape? {
        let bounds = boundingBox(points)
        let corners = detectCorners(points)

        if corners.count < 3 {
            let cx = bounds.midX, cy = bounds.midY
            var rx = bounds.width / 2, ry = bounds.height / 2
            // Proportional constraining: a nearly-round ellipse becomes a
            // perfect circle rather than staying slightly oblong.
            if rx > 0, ry > 0, abs(rx - ry) <= 0.15 * max(rx, ry) {
                let r = (rx + ry) / 2
                rx = r; ry = r
            }
            return .ellipse(center: CGPoint(x: cx, y: cy), radiusX: rx, radiusY: ry)
        }

        if corners.count == 4 {
            return .polygon(regularizedRectangle(corners))
        }

        // Triangle, or a general polygon for 5+ corners — cap so a noisy
        // trace doesn't produce an absurd number of vertices.
        let vertices = corners.count > 8 ? Array(corners.prefix(8)) : corners
        return .polygon(vertices)
    }

    /// Finds corner points by resampling to uniform arc-length spacing, then
    /// looking for local maxima in the turning angle (the angle between the
    /// incoming and outgoing direction at each point) above a threshold,
    /// merging any that land close together into one.
    private static func detectCorners(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 8 else { return [] }
        // Wider window on longer paths so noise doesn't register as corners.
        let window = max(2, points.count / 24)

        var turning: [CGFloat] = Array(repeating: 0, count: points.count)
        for i in points.indices {
            let a = points[max(0, i - window)]
            let b = points[i]
            let c = points[min(points.count - 1, i + window)]
            let v1 = CGVector(dx: b.x - a.x, dy: b.y - a.y)
            let v2 = CGVector(dx: c.x - b.x, dy: c.y - b.y)
            turning[i] = abs(angleBetween(v1, v2))
        }

        let cornerThreshold: CGFloat = 32 * .pi / 180
        var candidates: [Int] = []
        for i in points.indices where turning[i] >= cornerThreshold {
            // Keep only local maxima within a neighborhood.
            let lo = max(0, i - window), hi = min(points.count - 1, i + window)
            if turning[i] == turning[lo...hi].max() { candidates.append(i) }
        }

        // Merge candidates that are close together (same physical corner
        // detected at several nearby indices).
        var merged: [Int] = []
        let mergeRadius = max(1, points.count / 16)
        for i in candidates {
            if let last = merged.last, i - last <= mergeRadius { continue }
            merged.append(i)
        }
        return merged.map { points[$0] }
    }

    /// Regularizes 4 detected corners into a true rectangle: opposite sides
    /// forced parallel and perpendicular to each other, with proportional
    /// constraining (near-equal sides become a perfect square) and a light
    /// snap to axis-aligned when the drawn rectangle was close to level.
    private static func regularizedRectangle(_ corners: [CGPoint]) -> [CGPoint] {
        let center = centroid(corners)
        // Order around the center so edges connect the right neighbors
        // regardless of the order corners were detected in.
        let ordered = corners.sorted {
            atan2($0.y - center.y, $0.x - center.x) < atan2($1.y - center.y, $1.x - center.x)
        }
        guard ordered.count == 4 else { return corners }

        let edgeVectors = (0..<4).map { i in
            CGVector(dx: ordered[(i + 1) % 4].x - ordered[i].x, dy: ordered[(i + 1) % 4].y - ordered[i].y)
        }
        var angleA = atan2(edgeVectors[0].dy, edgeVectors[0].dx)
        angleA = snappedAxisAngle(angleA) ?? angleA

        let widths  = [length(edgeVectors[0]), length(edgeVectors[2])]
        let heights = [length(edgeVectors[1]), length(edgeVectors[3])]
        var width  = widths.reduce(0, +) / 2
        var height = heights.reduce(0, +) / 2
        // Proportional constraining: near-equal sides become an exact square.
        if abs(width - height) <= 0.12 * max(width, height) {
            let s = (width + height) / 2
            width = s; height = s
        }

        let dirA = CGVector(dx: cos(angleA), dy: sin(angleA))
        let dirB = CGVector(dx: -dirA.dy, dy: dirA.dx)
        let hw = width / 2, hh = height / 2
        return [
            CGPoint(x: center.x - dirA.dx * hw - dirB.dx * hh, y: center.y - dirA.dy * hw - dirB.dy * hh),
            CGPoint(x: center.x + dirA.dx * hw - dirB.dx * hh, y: center.y + dirA.dy * hw - dirB.dy * hh),
            CGPoint(x: center.x + dirA.dx * hw + dirB.dx * hh, y: center.y + dirA.dy * hw + dirB.dy * hh),
            CGPoint(x: center.x - dirA.dx * hw + dirB.dx * hh, y: center.y - dirA.dy * hw + dirB.dy * hh),
        ]
    }

    // MARK: - Axis & grid snapping (applied by the caller to line/arrow endpoints too)

    /// Snaps `angle` (radians) to the nearest 0/45/90/135° axis if within
    /// `tolerance`, else returns nil (leave the drawn angle as-is).
    static func snappedAxisAngle(_ angle: CGFloat, toleranceDegrees: CGFloat = 10) -> CGFloat? {
        let degrees = angle * 180 / .pi
        let normalized = degrees.truncatingRemainder(dividingBy: 180)
        let positive = normalized < 0 ? normalized + 180 : normalized
        let axes: [CGFloat] = [0, 45, 90, 135, 180]
        guard let nearest = axes.min(by: { abs($0 - positive) < abs($1 - positive) }) else { return nil }
        guard abs(nearest - positive) <= toleranceDegrees else { return nil }
        let delta = nearest - positive
        return (degrees + delta) * .pi / 180
    }

    /// Snaps `point` to the nearest grid intersection if within `radius`.
    static func snappedToGrid(_ point: CGPoint, spacing: CGFloat, radius: CGFloat) -> CGPoint {
        guard spacing > 0 else { return point }
        let nearestX = (point.x / spacing).rounded() * spacing
        let nearestY = (point.y / spacing).rounded() * spacing
        let dx = nearestX - point.x, dy = nearestY - point.y
        guard hypot(dx, dy) <= radius else { return point }
        return CGPoint(x: nearestX, y: nearestY)
    }

    // MARK: - Small geometry helpers

    private static func resample(_ points: [CGPoint], targetSpacing: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var result: [CGPoint] = [points[0]]
        var carry: CGFloat = 0
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            var segLen = distance(a, b)
            var last = a
            while carry + segLen >= targetSpacing {
                let t = (targetSpacing - carry) / segLen
                let p = CGPoint(x: last.x + (b.x - last.x) * t, y: last.y + (b.y - last.y) * t)
                result.append(p)
                segLen -= (targetSpacing - carry)
                last = p
                carry = 0
            }
            carry += segLen
        }
        if let lastPoint = points.last, result.last.map({ distance($0, lastPoint) > 0.5 }) ?? true {
            result.append(lastPoint)
        }
        return result
    }

    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var total: CGFloat = 0
        for i in 1..<points.count { total += distance(points[i - 1], points[i]) }
        return total
    }

    private static func perpendicularDistance(_ p: CGPoint, from a: CGPoint, to b: CGPoint) -> CGFloat {
        let len = distance(a, b)
        guard len > 0 else { return distance(p, a) }
        // |cross product| / |ab| = distance from p to the infinite line ab.
        let cross = (b.x - a.x) * (a.y - p.y) - (a.x - p.x) * (b.y - a.y)
        return abs(cross) / len
    }

    private static func length(_ v: CGVector) -> CGFloat { hypot(v.dx, v.dy) }

    private static func angleBetween(_ v1: CGVector, _ v2: CGVector) -> CGFloat {
        let a1 = atan2(v1.dy, v1.dx), a2 = atan2(v2.dy, v2.dx)
        var delta = a2 - a1
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        return delta
    }
}
