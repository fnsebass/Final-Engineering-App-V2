//
//  EquationOCR.swift
//  Tolerance
//
//  Phase 6 bridge: turns the circled handwritten ink (rendered to an image)
//  into a text string that the UnitChecker and the AI reviewer can consume.
//
//  Uses Vision's on-device text recognizer. Handwriting OCR is imperfect,
//  especially for math symbols, which is exactly why the results panel lets the
//  user correct the recognized text before re-running the checks.
//

#if os(iOS)
import UIKit
import Vision

enum EquationOCR {

    /// Recognize text in an image. Returns an empty string if nothing is found.
    static func recognize(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Math isn't natural language; language correction tends to "fix"
        // symbols into words, so turn it off.
        request.usesLanguageCorrection = false

        do {
            let observations = try await request.perform(on: cgImage)
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
    }
}
#endif
