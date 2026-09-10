//
//  GeminiAPIKeySettingsView.swift
//  Tolerance
//
//  Secure entry for the user's Gemini Vision API key. Stored in UserDefaults
//  and read directly by GeminiVisionService for the Box Verify feature.
//

import SwiftUI

struct GeminiAPIKeySettingsView: View {
    @State private var geminiKey: String = GeminiVisionService.apiKey

    var body: some View {
        Form {
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
                Text("Used to power multimodal diagram analysis and image processing in the Box-to-Verify feature. Get a free key at aistudio.google.com. Stored locally on device and never sent anywhere except directly to Google's Gemini API.")
                    .font(.caption)
            }
        }
        .navigationTitle("Gemini Vision API Key")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack { GeminiAPIKeySettingsView() }
}
