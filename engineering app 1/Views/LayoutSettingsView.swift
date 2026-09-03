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

struct LayoutSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(LayoutPrefs.showDates) private var showDates = true
    @AppStorage(LayoutPrefs.accentRaw) private var accentRaw = LayoutAccent.blue.rawValue
    @AppStorage(LayoutPrefs.defaultPaperStyle) private var defaultPaperStyleRaw = PaperStyle.grid.rawValue
    @AppStorage(LayoutPrefs.aiVerbose) private var aiVerbose = true

    // Gemini API key — stored in UserDefaults (same key GeminiVisionService reads).
    @State private var geminiKey: String = GeminiVisionService.apiKey

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

                // MARK: - Gemini Vision API Key
                Section {
                    SecureField("Paste API key here", text: $geminiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: geminiKey) { _, newKey in
                            GeminiVisionService.apiKey = newKey
                        }
                    if geminiKey.isEmpty {
                        Label("Key required for Box Verify mode", systemImage: "key.slash")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Label("Key saved", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Gemini Vision API Key")
                } footer: {
                    Text("Used by the Box-to-Verify feature. Get a free key at aistudio.google.com. Stored locally on device.")
                        .font(.caption)
                }

                // MARK: - AI Response Style
                Section("On-Device AI Response Style") {
                    Toggle("Full explanations", isOn: $aiVerbose)
                    Text("When off, the on-device AI gives a brief answer check instead of a full step-by-step walkthrough.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

                // MARK: - Support & Legal
                Section("Support & Legal") {
                    Link(destination: URL(string: "https://github.com/fnsebass/Final-Engineering-App-V2")!) {
                        Label("Support", systemImage: "questionmark.circle")
                    }
                    Link(destination: URL(string: "https://github.com/fnsebass/Final-Engineering-App-V2")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
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
