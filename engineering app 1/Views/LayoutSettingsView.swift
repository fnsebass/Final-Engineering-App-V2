//
//  LayoutSettingsView.swift
//  Tolerance
//
//  Preferences for how the home workspace and new items look.
//  Opened from the settings sheet in HomeView and backed by @AppStorage.
//

import SwiftUI

/// Keys shared across HomeView and editor settings.
enum LayoutPrefs {
    static let showDates = "layout.showDates"
    static let foldersFirst = "layout.foldersFirst"
    static let accentRaw = "layout.accent"
    static let defaultPaperStyle = "layout.defaultPaperStyle"
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

struct LayoutSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(LayoutPrefs.showDates) private var showDates = true
    @AppStorage(LayoutPrefs.accentRaw) private var accentRaw = LayoutAccent.blue.rawValue
    @AppStorage(LayoutPrefs.defaultPaperStyle) private var defaultPaperStyleRaw = PaperStyle.grid.rawValue

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Paper Defaults
                Section("New Derivation Default") {
                    Picker("Default Paper Style", selection: $defaultPaperStyleRaw) {
                        ForEach(PaperStyle.allCases) { style in
                            Label(style.displayName, systemImage: style.systemImage)
                                .tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // MARK: - Display Settings
                Section("Card Display") {
                    Toggle("Show edited dates on cards", isOn: $showDates)
                }

                // MARK: - Accent Color Selection
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
            }
            .navigationTitle("Customize Layout")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 380)
    }
}

#Preview {
    LayoutSettingsView()
}
