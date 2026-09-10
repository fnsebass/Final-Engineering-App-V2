//
//  TutorInteractionsSettingsView.swift
//  Tolerance
//
//  How the on-device/Gemini tutor explains itself: hint style, step-by-step
//  preference, and a custom prompting note appended to every AI request.
//

import SwiftUI

enum HintMode: String, CaseIterable, Identifiable {
    case minimal, guided, full
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimal: return "Minimal Hints"
        case .guided:  return "Guided Hints"
        case .full:    return "Full Walkthrough"
        }
    }
}

struct TutorInteractionsSettingsView: View {
    @AppStorage("settings.tutor.hintMode") private var hintModeRaw = HintMode.guided.rawValue
    @AppStorage(LayoutPrefs.aiVerbose) private var aiVerbose = true
    @AppStorage("settings.tutor.customPrompt") private var customPrompt = ""

    var body: some View {
        Form {
            Section {
                Picker("Hint Style", selection: $hintModeRaw) {
                    ForEach(HintMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
            } header: {
                Text("AI Hint Generation")
            } footer: {
                Text("Minimal gives a single hint instead of a full solve; Full adds concept explanations. Applies to the on-device tutor.")
                    .font(.caption)
            }

            Section {
                Toggle("Full Step-by-Step Explanations", isOn: $aiVerbose)
            } footer: {
                Text("When off, \"Ask AI\" uses the brief answer-check response instead of the full step-by-step walkthrough.")
                    .font(.caption)
            }

            Section {
                TextField("e.g. \"Always show units\" or \"Prefer SI units\"", text: $customPrompt, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Custom Prompting")
            } footer: {
                Text("Appended to every on-device tutor request. Not used by the Gemini Vision Box Verify feature.")
                    .font(.caption)
            }
        }
        .navigationTitle("Tutor Interactions")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack { TutorInteractionsSettingsView() }
}
