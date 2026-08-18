//
//  PaperTheme.swift
//  Tolerance
//
//  Helpers for the per-notepad paper color, the auto-contrast pen color, and
//  the faint grid color. Colors are stored on the model as "#RRGGBB" strings.
//

#if os(iOS)
import SwiftUI
import UIKit

enum PaperTheme {
    /// Preset paper colors offered in settings: (display name, hex).
    static let presets: [(name: String, hex: String)] = [
        ("White", "#FFFFFF"),
        ("Cream", "#FBF3DE"),
        ("Gray", "#F2F2F7"),
        ("Blue tint", "#EAF2FB"),
        ("Dark", "#1C1C1E"),
        ("Black", "#000000"),
    ]

    static func uiColor(fromHex hex: String) -> UIColor {
        var string = hex.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt64(string, radix: 16) else { return .white }
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1)
    }

    static func color(fromHex hex: String) -> Color { Color(uiColor: uiColor(fromHex: hex)) }

    static func hex(from color: Color) -> String { hex(from: UIColor(color)) }

    static func hex(from uiColor: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    /// Perceived brightness of a paper color, 0 (black) … 1 (white).
    private static func luminance(ofHex hex: String) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor(fromHex: hex).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// The pen color: always the strong opposite of the paper, so ink is legible.
    static func inkUIColor(forPaperHex hex: String) -> UIColor {
        luminance(ofHex: hex) > 0.5 ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.95, alpha: 1)
    }

    static func inkColor(forPaperHex hex: String) -> Color { Color(uiColor: inkUIColor(forPaperHex: hex)) }

    /// A faint version of the ink color for grid lines.
    static func gridUIColor(forPaperHex hex: String) -> UIColor {
        inkUIColor(forPaperHex: hex).withAlphaComponent(0.16)
    }
}
#endif
