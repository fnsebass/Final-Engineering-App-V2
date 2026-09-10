//
//  ThemeSettingsView.swift
//  Tolerance
//
//  Light/dark mode, OLED black mode, accent color, and interface scale.
//  `isDarkMode` and `LayoutPrefs.accentRaw` are also read directly by
//  HomeView/engineering_app_1App, so their keys and types stay unchanged.
//

import SwiftUI

enum LayoutPrefs {
    static let showDates = "layout.showDates"
    static let foldersFirst = "layout.foldersFirst"
    static let accentRaw = "layout.accent"
    static let defaultPaperStyle = "layout.defaultPaperStyle"
    static let defaultPaperColorHex = "layout.defaultPaperColorHex"
    static let aiVerbose = "ai.verbose"
}

enum LayoutAccent: String, CaseIterable, Identifiable {
    case blue, purple, green, orange, pink
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        }
    }
}

/// Maps the 0.85–1.3 Interface Scale slider onto the nearest system Dynamic
/// Type size, so "Interface Scale" resizes real text/controls throughout the
/// app instead of just being a saved number.
enum InterfaceScale {
    static func dynamicTypeSize(for scale: Double) -> DynamicTypeSize {
        switch scale {
        case ..<0.90:   return .small
        case ..<0.98:   return .medium
        case ..<1.03:   return .large
        case ..<1.10:   return .xLarge
        case ..<1.20:   return .xxLarge
        default:        return .xxxLarge
        }
    }
}

struct ThemeSettingsView: View {
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("settings.theme.oledBlack") private var oledBlack = false
    @AppStorage(LayoutPrefs.accentRaw) private var accentRaw = LayoutAccent.blue.rawValue
    @AppStorage("settings.theme.interfaceScale") private var interfaceScale = 1.0

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Dark Mode", isOn: $isDarkMode)
                Toggle("OLED Black Mode", isOn: $oledBlack)
                    .disabled(!isDarkMode)
            }
            if !isDarkMode {
                UnwiredNote("OLED Black Mode requires Dark Mode to be on.")
                    .listRowSeparator(.hidden)
            } else if oledBlack {
                Label("New notepads default to a pure black background instead of the default paper color.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .listRowSeparator(.hidden)
            }

            Section("Accent Color") {
                HStack(spacing: 16) {
                    ForEach(LayoutAccent.allCases) { accent in
                        Circle()
                            .fill(accent.color)
                            .frame(width: 32, height: 32)
                            .overlay {
                                if accentRaw == accent.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            .onTapGesture {
                                accentRaw = accent.rawValue
                            }
                            .accessibilityLabel(accent.rawValue.capitalized)
                            .accessibilityAddTraits(accentRaw == accent.rawValue ? .isSelected : [])
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Slider(value: $interfaceScale, in: 0.85...1.3, step: 0.05)
                    Text("\(Int(interfaceScale * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Interface Scale")
            } footer: {
                Text("Scales system text and controls throughout the app via Dynamic Type. Doesn't resize the drawing canvas itself.")
                    .font(.caption)
            }
        }
        .navigationTitle("Theme")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack { ThemeSettingsView() }
}
