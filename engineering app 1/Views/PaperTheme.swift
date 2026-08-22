//
//  PaperTheme.swift
//  Tolerance
//
//  Helpers for per-notepad paper color, auto-contrast pen color, and
//  faint grid color. Colors are persisted on the model as "#RRGGBB" strings.
//

#if os(iOS)
import SwiftUI
import UIKit

struct PaperThemePreset: Identifiable, Sendable {
    let name: String
    let hex: String
    var id: String { hex }
}

enum PaperTheme {
    /// Preset paper colors offered in settings.
    static let presets: [PaperThemePreset] = [
        PaperThemePreset(name: "White",     hex: "#FFFFFF"),
        PaperThemePreset(name: "Cream",     hex: "#FBF3DE"),
        PaperThemePreset(name: "Gray",      hex: "#F2F2F7"),
        PaperThemePreset(name: "Blue Tint", hex: "#EAF2FB"),
        PaperThemePreset(name: "Dark",      hex: "#1C1C1E"),
        PaperThemePreset(name: "Black",     hex: "#000000")
    ]

    // MARK: - Hex Conversion

    static func uiColor(fromHex hex: String) -> UIColor {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        
        // Support 6-character RRGGBB strings
        guard string.count == 6, let value = UInt64(string, radix: 16) else {
            return .white
        }
        
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    static func color(fromHex hex: String) -> Color {
        Color(uiColor: uiColor(fromHex: hex))
    }

    static func hex(from color: Color) -> String {
        hex(from: UIColor(color))
    }

    static func hex(from uiColor: UIColor) -> String {
        // Ensure color is converted to sRGB space before reading red/green/blue components
        guard let srgbColor = uiColor.cgColor.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!,
            intent: .defaultIntent,
            options: nil
        ), let components = srgbColor.components, components.count >= 3 else {
            return "#FFFFFF"
        }

        let r = max(0, min(1, components[0]))
        let g = max(0, min(1, components[1]))
        let b = max(0, min(1, components[2]))

        return String(format: "#%02X%02X%02X", Int(r * 255.0), Int(g * 255.0), Int(b * 255.0))
    }

    // MARK: - Relative Luminance (WCAG Standard)

    /// Perceived relative luminance of a paper color using sRGB gamma expansion (0 = black, 1 = white).
    private static func relativeLuminance(ofHex hex: String) -> CGFloat {
        let uiCol = uiColor(fromHex: hex)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiCol.getRed(&r, green: &g, blue: &b, alpha: &a)

        func linearize(_ component: CGFloat) -> CGFloat {
            return component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        let rLin = linearize(r)
        let gLin = linearize(g)
        let bLin = linearize(b)

        return 0.2126 * rLin + 0.7152 * gLin + 0.0722 * bLin
    }

    // MARK: - Contrast Calculations

    /// Pen color: high-contrast dark or light ink determined by paper background luminance.
    static func inkUIColor(forPaperHex hex: String) -> UIColor {
        relativeLuminance(ofHex: hex) > 0.45
            ? UIColor(red: 0, green: 0, blue: 0, alpha: 1)   // pure black #000000
            : UIColor(red: 1, green: 1, blue: 1, alpha: 1)   // pure white #FFFFFF
    }

    static func inkColor(forPaperHex hex: String) -> Color {
        Color(uiColor: inkUIColor(forPaperHex: hex))
    }

    /// Grid line color: derived from ink color with transparency applied.
    static func gridUIColor(forPaperHex hex: String) -> UIColor {
        inkUIColor(forPaperHex: hex).withAlphaComponent(0.25)
    }
}
#endif
