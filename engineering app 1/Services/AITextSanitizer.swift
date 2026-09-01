import Foundation

/// Strips markdown formatting and LaTeX delimiters from AI-generated text,
/// leaving plain readable English and Unicode math symbols (∫, √, ×, →, ∞).
enum AITextSanitizer: Sendable {
    static func run(_ text: String) -> String {
        var s = text

        // Remove markdown bold/italic markers
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.replacingOccurrences(of: "__", with: "")

        // Remove LaTeX math delimiters (keep content inside)
        for token in ["\\[", "\\]", "\\(", "\\)", "$$", "\\,", "\\;", "\\!"] {
            s = s.replacingOccurrences(of: token, with: "")
        }
        s = s.replacingOccurrences(of: "$", with: "")

        // Process line by line: strip # headers and leading list bullets
        let lines = s.components(separatedBy: "\n").map { raw -> String in
            var line = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            if line.first == "#" {
                while line.hasPrefix("#") { line = String(line.dropFirst()) }
                line = line.trimmingCharacters(in: CharacterSet(charactersIn: " "))
            }
            for prefix in ["- ", "• ", "* ", "· "] {
                if line.hasPrefix(prefix) { line = String(line.dropFirst(prefix.count)); break }
            }
            return line
        }

        s = lines.joined(separator: "\n")

        while s.contains("\n\n\n") {
            s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
