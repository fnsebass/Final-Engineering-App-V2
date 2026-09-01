import Foundation
import UIKit

// MARK: - Gemini Vision API client

/// Sends a cropped PNG image to Gemini 3.6 Flash Vision and returns a plain-text analysis.
///
/// Usage:
///   1. Store the user's API key once:  `GeminiVisionService.apiKey = "AIza…"`
///   2. Call from async context:        `let text = try await GeminiVisionService.verify(imageData: pngData)`
struct GeminiVisionService {

    // MARK: - Configuration (persisted in UserDefaults)

    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: "gemini.apiKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "gemini.apiKey") }
    }

    // Gemini 3.6 Flash is multi-modal (vision) and fast — ideal for quick equation checks.
    private static let modelID  = "gemini-3.6-flash"
    private static let endpoint =
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent"

    // MARK: - System prompt

    private static let systemPrompt = """
    You are an expert math, physics, and engineering solver. The image shows handwritten or typed \
    work from a student's iPad. Your primary job is to SOLVE and COMPUTE, not to describe.

    Priority order — pick the first that applies:

    1. SOLVE FOR UNKNOWNS: If the image contains an equation or system with an unknown variable \
    (x, y, θ, v, F, etc.), solve it completely. Show only the key algebraic steps and the final \
    numeric or symbolic answer. Do not just restate the equation.

    2. EVALUATE MISSING VALUES: If something is set up but not computed — a limit, integral, \
    derivative, sum, matrix determinant, force resultant, voltage, etc. — evaluate it and give \
    the exact answer (simplified). Show brief working.

    3. COMPLETE PARTIAL WORK: If the student has started a solution but stopped, continue from \
    where they left off and finish it.

    4. VERIFY AND CORRECT: Only if the problem appears fully solved — check every step. If wrong, \
    identify the exact error and give the corrected answer. If correct, confirm briefly and add \
    one useful insight (e.g. a faster method, a physical interpretation).

    5. DIAGRAMS: For free-body diagrams, circuits, trusses, or beam problems — extract the \
    unknowns, write the governing equations, and solve for the requested quantities.

    Rules:
    - Lead with the answer or the solving steps immediately. Never open by restating the problem.
    - Plain text only. No markdown, no asterisks, no LaTeX delimiters.
    - Use Unicode math symbols: ∫ √ × ÷ → ≤ ≥ ∞ ∂ π ² ³ Σ ± ≈
    - Maximum 300 words. Be concise and numeric wherever possible.
    - If the image is blank, blurry, or has no math content, say so in one sentence.
    """

    // MARK: - API call

    /// Sends `imageData` (PNG bytes) to Gemini Vision and returns the text analysis.
    ///
    /// - Throws: `GeminiError.noAPIKey` if no key is configured.
    ///           `GeminiError.apiError` if the server returns a non-200 status.
    ///           `GeminiError.emptyResponse` if Gemini returns no text.
    static func verify(imageData: Data) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.noAPIKey }
        guard let url = URL(string: "\(endpoint)?key=\(apiKey)") else {
            throw GeminiError.invalidURL
        }

        // Shrink the image before sending: full-screen retina PNGs can be 3-6 MB of
        // base64, which dominates latency. Cap the long side at 1024 pt and re-encode
        // as JPEG at 80% quality. This typically cuts payload from ~4 MB to ~150 KB.
        let (sendData, mimeType) = compressedImageData(from: imageData)
        let base64Image = sendData.base64EncodedString()

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [ ["text": systemPrompt] ]
            ],
            "contents": [[
                "role": "user",
                "parts": [
                    [
                        "inline_data": [
                            "mime_type": mimeType,
                            "data": base64Image
                        ]
                    ],
                    [
                        "text": "Solve or evaluate the work shown."
                    ]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 400
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let http = httpResponse as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        guard http.statusCode == 200 else {
            // Attempt to extract the structured error message from Gemini's error envelope.
            let detail = (try? JSONDecoder().decode(GeminiAPIError.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(http.statusCode)"
            throw GeminiError.apiError(detail)
        }

        let parsed = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = parsed.candidates.first?.content.parts.first?.text,
              !text.isEmpty else {
            throw GeminiError.emptyResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Image compression

    /// Resizes the image so its longest side is at most `maxPx` points, then
    /// re-encodes as JPEG at 80% quality. Falls back to the original PNG data
    /// if UIImage cannot be decoded. Returns (data, mimeType).
    private static func compressedImageData(from png: Data,
                                            maxPx: CGFloat = 1024) -> (Data, String) {
        guard let src = UIImage(data: png) else { return (png, "image/png") }

        let w = src.size.width, h = src.size.height
        let scale = min(maxPx / max(w, h), 1.0)
        let newSize = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized  = renderer.image { _ in src.draw(in: CGRect(origin: .zero, size: newSize)) }

        if let jpg = resized.jpegData(compressionQuality: 0.8) {
            return (jpg, "image/jpeg")
        }
        return (png, "image/png")
    }
}

// MARK: - Errors

enum GeminiError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case apiError(String)
    case emptyResponse
    case captureFailure

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Gemini API key not configured. Add it in Settings > Appearance & Tools."
        case .invalidURL:
            return "Invalid API endpoint URL."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .apiError(let msg):
            return "Gemini error: \(msg)"
        case .emptyResponse:
            return "Gemini returned an empty response. Try again."
        case .captureFailure:
            return "Could not capture the selected region. Try a larger selection."
        }
    }
}

// MARK: - Codable response shapes (private — only used here)

private struct GeminiResponse: Decodable {
    let candidates: [Candidate]
    struct Candidate: Decodable {
        let content: Content
    }
    struct Content: Decodable {
        let parts: [Part]
    }
    struct Part: Decodable {
        let text: String?
    }
}

private struct GeminiAPIError: Decodable {
    let error: ErrorDetail
    struct ErrorDetail: Decodable {
        let message: String
    }
}
