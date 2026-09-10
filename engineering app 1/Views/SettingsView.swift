//
//  SettingsView.swift
//  Tolerance
//
//  Top-level settings hub, opened from HomeView. Groups all preferences
//  into GENERAL / WRITING / INTELLIGENCE / ACCOUNT & SYSTEM sections, each
//  containing a NavigationLink to a dedicated detail screen.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("General") {
                    NavigationLink { GeneralSettingsView() } label: {
                        SettingsRow(icon: "gearshape.fill", tint: .gray, title: "General")
                    }
                    NavigationLink { ThemeSettingsView() } label: {
                        SettingsRow(icon: "paintpalette.fill", tint: .purple, title: "Theme")
                    }
                    NavigationLink { PaperLayoutSettingsView() } label: {
                        SettingsRow(icon: "square.grid.3x3.fill", tint: .indigo, title: "Paper & Layout")
                    }
                }

                Section("Writing") {
                    NavigationLink { PenStylusSettingsView() } label: {
                        SettingsRow(icon: "pencil.tip", tint: .blue, title: "Pen & Stylus")
                    }
                    NavigationLink { PenButtonsSettingsView() } label: {
                        SettingsRow(icon: "button.programmable", tint: .teal, title: "Pen Buttons")
                    }
                    NavigationLink { GesturesTouchSettingsView() } label: {
                        SettingsRow(icon: "hand.draw.fill", tint: .cyan, title: "Gestures & Touch")
                    }
                }

                Section("Intelligence") {
                    NavigationLink { TutorRecognitionSettingsView() } label: {
                        SettingsRow(icon: "sparkles", tint: .pink, title: "Tutor & Recognition")
                    }
                    NavigationLink { TutorInteractionsSettingsView() } label: {
                        SettingsRow(icon: "bubble.left.and.text.bubble.right.fill", tint: .orange, title: "Tutor Interactions")
                    }
                    NavigationLink { GeminiAPIKeySettingsView() } label: {
                        SettingsRow(icon: "key.fill", tint: .yellow, title: "Gemini Vision API Key")
                    }
                }

                Section("Account & System") {
                    NavigationLink { AccountSettingsView() } label: {
                        SettingsRow(icon: "person.crop.circle.fill", tint: .blue, title: "Account")
                    }
                    NavigationLink { SyncSettingsView() } label: {
                        SettingsRow(icon: "icloud.fill", tint: .green, title: "Sync")
                    }
                    NavigationLink { SupportLegalSettingsView() } label: {
                        SettingsRow(icon: "questionmark.circle.fill", tint: .secondary, title: "Support & Legal")
                    }
                }
            }
            .navigationTitle("Settings")
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
        .frame(minWidth: 360, minHeight: 480)
    }
}

// MARK: - Shared row style

/// An icon-badge + title row used for every entry in the settings hub.
struct SettingsRow: View {
    let icon: String
    let tint: Color
    let title: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint, in: RoundedRectangle(cornerRadius: 7))
        }
    }
}

// MARK: - Shared "not yet wired" footer note

/// Several settings below describe capabilities (hardware pen-button events, real-time
/// gesture recognition, cloud sync engines, account management) that this app doesn't
/// implement yet. The preference is still saved, but flagging it here keeps controls from
/// implying an effect they don't have.
struct UnwiredNote: View {
    let text: String

    init(_ text: String = "Saved as a preference, but not yet connected to app behavior.") {
        self.text = text
    }

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    SettingsView()
}
