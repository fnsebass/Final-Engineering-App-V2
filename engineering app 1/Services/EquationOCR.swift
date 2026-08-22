//
//  EquationOCR.swift
//  Tolerance
//
//  Recognizes handwritten math from a rasterized UIImage using Vision.
//
//  Two-pass result processing (both inline in the background Task to avoid
//  main-actor boundary crossings with Vision types):
//
//    Pass 1 — bounding-box fraction detection:
//      Two Vision observations that sit directly above each other (very small
//      vertical gap, horizontally co-centred) are joined with "/" to reconstruct
//      fraction notation split by handwriting layout (e.g. "d" above "dx" → "d/dx",
//      which Vision otherwise gives as two separate text blocks).
//
//    Pass 2 — symbol normalisation:
//      Corrects common OCR misreadings into proper Unicode math forms:
//      S/J (leading, followed by differential) → ∫, oo → ∞, <= → ≤, etc.
//

#if os(iOS)
import UIKit
import Vision

enum EquationOCR {

    /// Hints that guide Vision's text recogniser toward common math tokens.
    /// Captured before entering Task.detached to avoid actor-boundary issues.
    private static let customMathWords: [String] = [
        // Integrals
        "∫", "∬", "∭", "∮", "integral",
        // Derivatives
        "d/dx", "d/dy", "d/dt", "d/dz", "d/dr", "d/dθ",
        "d²/dx²", "d²/dy²", "d³/dx³",
        "∂", "∂/∂x", "∂/∂y", "∂/∂t", "∂/∂z",
        "∂f/∂x", "∂f/∂y", "∂f/∂t", "∂²f/∂x²", "∂²f/∂y²",
        // Prime notation
        "f'(x)", "f''(x)", "y'", "y''", "f'", "f''",
        // Differentials
        "dx", "dy", "dz", "dt", "du", "dv",
        "dθ", "dφ", "dψ", "dr", "ds", "dA", "dV",
        // Limits & series
        "lim", "lim→0", "lim→∞", "Σ", "Π", "∏", "→∞", "→0", "→",
        // Trig & transcendental
        "sin", "cos", "tan", "cot", "sec", "csc",
        "arcsin", "arccos", "arctan", "atan2",
        "sinh", "cosh", "tanh", "coth",
        "ln", "log", "log₂", "log₁₀", "exp", "sqrt",
        // Infinity
        "∞", "inf",
        // Greek
        "α", "β", "γ", "δ", "ε", "ζ", "η", "θ",
        "ι", "κ", "λ", "μ", "ν", "ξ", "π", "ρ",
        "σ", "τ", "υ", "φ", "χ", "ψ", "ω",
        "Γ", "Δ", "Θ", "Λ", "Ξ", "Π", "Σ", "Φ", "Ψ", "Ω",
        // Engineering units
        "kg", "m/s", "m/s²", "N·m", "N/m²", "Pa", "kPa", "MPa", "GPa",
        "Hz", "kHz", "MHz", "GHz", "Ω", "ohm", "mol", "mol/L", "rad", "rad/s",
        // Common function expressions
        "f(x)", "g(x)", "h(x)", "F(x)", "G(x)",
    ]

    /// Recognize handwritten math in `image`. Returns an empty string if nothing
    /// is found. The image should be pre-composited on a white background.
    static func recognize(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }

        // Capture the word list on the current actor before entering the
        // detached background task.
        let words = customMathWords

        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel       = .accurate
            request.usesLanguageCorrection = false  // language correction mangles math
            request.minimumTextHeight      = 0.01   // catch superscripts/subscripts
            request.customWords            = words

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                guard let results = request.results, !results.isEmpty else { return "" }

                // ── Pass 1: fraction / derivative detection ───────────────────
                // Sort top-to-bottom (Vision y=0 is image bottom; higher minY = top).
                let sorted = results.sorted { $0.boundingBox.minY > $1.boundingBox.minY }

                var parts: [String] = []
                var used  = Set<Int>()

                for (i, obs) in sorted.enumerated() {
                    guard !used.contains(i) else { continue }

                    let topBox  = obs.boundingBox
                    let topText = obs.topCandidates(1).first?.string ?? ""

                    // Pair with the next observation if they are stacked as a fraction:
                    //   • positive but tiny vertical gap  (< 5 % of image height)
                    //   • horizontal centres close         (< 12 % of image width apart)
                    //   • some horizontal overlap
                    // This reconstructs "d" above "dx" as "d/dx", etc.
                    if i + 1 < sorted.count, !used.contains(i + 1) {
                        let btmObs  = sorted[i + 1]
                        let btmBox  = btmObs.boundingBox
                        let btmText = btmObs.topCandidates(1).first?.string ?? ""

                        let vertGap     = topBox.minY  - btmBox.maxY
                        let hCenterDiff = abs(topBox.midX - btmBox.midX)
                        let hOverlap    = min(topBox.maxX, btmBox.maxX)
                                        - max(topBox.minX, btmBox.minX)

                        if vertGap >= 0, vertGap < 0.05,
                           hCenterDiff < 0.12, hOverlap > 0 {
                            parts.append("\(topText)/\(btmText)")
                            used.insert(i); used.insert(i + 1)
                            continue
                        }
                    }

                    used.insert(i)
                    parts.append(topText)
                }

                var s = parts
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // ── Pass 2: symbol normalisation ──────────────────────────────

                // ASCII operator pairs → proper Unicode
                for (from, to): (String, String) in [
                    ("-->", "→"), ("->",  "→"),
                    ("==>", "⟹"), ("=>",  "⟹"),
                    ("<=",  "≤"), (">=",  "≥"),
                    ("!=",  "≠"), ("<>",  "≠"),
                    ("+-",  "±"), ("-+",  "∓"),
                ] { s = s.replacingOccurrences(of: from, with: to) }

                // Isolated "oo" / "0o" / "o0" as the written form of infinity
                for pat in [#"\boo\b"#, #"\b0o\b"#, #"\bo0\b"#] {
                    s = s.replacingOccurrences(of: pat, with: "∞",
                                               options: .regularExpression)
                }

                // "integral" spelled out
                s = s.replacingOccurrences(
                    of: #"\bintegral\b"#, with: "∫",
                    options: [.regularExpression, .caseInsensitive]
                )

                // Integral-sign heuristic:
                // Vision almost always reads ∫ as "S" or "J". When the expression
                // starts with a standalone S/J AND contains a differential term
                // (d followed by a single letter), the combination is an unmistakable
                // fingerprint of an integral: ∫ <expr> d<var>.
                let hasDiff = s.range(
                    of: #"\bd[a-zA-Zθφψωαβγδελμπστρ]\b"#,
                    options: .regularExpression
                ) != nil

                if hasDiff {
                    s = s.replacingOccurrences(
                        of: #"^(S|J)(?=\s)"#, with: "∫",
                        options: .regularExpression
                    )
                }

                return s

            } catch {
                return ""
            }
        }.value
    }
}
#endif
