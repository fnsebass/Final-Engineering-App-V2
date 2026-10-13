//
//  ShapeStrokeBuilder.swift
//  Tolerance
//
//  Turns a RecognizedShape (pure geometry — see ShapeRecognizer) into
//  actual PKStrokes, using the same "evenly-spaced control points along a
//  straight or curved path" technique PencilCanvasView's manual Shape tool
//  already uses for its own precise rectangle/circle/oval/triangle/arrow
//  strokes.
//
//  iOS/iPadOS only (PencilKit).
//

#if os(iOS)
import CoreGraphics
import UIKit
import PencilKit

enum ShapeStrokeBuilder {

    static func strokes(for shape: RecognizedShape, inkColor: UIColor, inkWidth: CGFloat) -> [PKStroke] {
        switch shape {
        case let .line(a, b):
            return [strokeAlong(points: interpolated(a, b), color: inkColor, width: inkWidth)]

        case let .arrow(start, tip):
            let headLen = max(20, hypot(tip.x - start.x, tip.y - start.y) * 0.2)
            let angle = atan2(tip.y - start.y, tip.x - start.x)
            let a1 = angle + .pi * 5 / 6
            let a2 = angle - .pi * 5 / 6
            let h1 = CGPoint(x: tip.x + headLen * cos(a1), y: tip.y + headLen * sin(a1))
            let h2 = CGPoint(x: tip.x + headLen * cos(a2), y: tip.y + headLen * sin(a2))
            return [
                strokeAlong(points: interpolated(start, tip), color: inkColor, width: inkWidth),
                strokeAlong(points: interpolated(tip, h1), color: inkColor, width: inkWidth),
                strokeAlong(points: interpolated(tip, h2), color: inkColor, width: inkWidth),
            ]

        case let .ellipse(center, rx, ry):
            let count = 72
            let points = (0...count).map { i -> CGPoint in
                let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(count)
                return CGPoint(x: center.x + rx * cos(t), y: center.y + ry * sin(t))
            }
            return [strokeAlong(points: points, color: inkColor, width: inkWidth)]

        case let .polygon(vertices):
            guard vertices.count >= 3 else { return [] }
            return (0..<vertices.count).map { i in
                let a = vertices[i], b = vertices[(i + 1) % vertices.count]
                return strokeAlong(points: interpolated(a, b), color: inkColor, width: inkWidth)
            }
        }
    }

    private static func interpolated(_ a: CGPoint, _ b: CGPoint) -> [CGPoint] {
        let len = hypot(b.x - a.x, b.y - a.y)
        let n = max(3, Int(len / 8) + 2)
        return (0..<n).map { i in
            let t = CGFloat(i) / CGFloat(n - 1)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }

    /// Builds a single stroke through `points` as-is — also used directly by
    /// SmartDrawOverlay's raw-freehand fallback when nothing was recognized.
    static func strokeAlong(points: [CGPoint], color: UIColor, width: CGFloat) -> PKStroke {
        let n = points.count
        let strokePoints = points.enumerated().map { i, p in
            PKStrokePoint(
                location: p,
                timeOffset: Double(i) / Double(max(n - 1, 1)),
                size: CGSize(width: width, height: width),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        let ink = PKInk(.pen, color: color)
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: strokePoints, creationDate: Date()))
    }
}
#endif
