//
//  GeneralSettingsView.swift
//  Tolerance
//
//  App language, handedness, default export format, and onboarding reset.
//

import SwiftUI

enum GeneralPrefs {
    static let language = "settings.general.language"
    static let handedness = "settings.general.handedness"
    static let defaultExportFormat = "settings.general.exportFormat"
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, spanish, french, german

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:  return "System"
        case .english: return "English"
        case .spanish: return "Español"
        case .french:  return "Français"
        case .german:  return "Deutsch"
        }
    }
}

enum Handedness: String, CaseIterable, Identifiable {
    case left, right

    var id: String { rawValue }
    var displayName: String { self == .left ? "Left-handed" : "Right-handed" }
    var systemImage: String { self == .left ? "hand.point.up.left.fill" : "hand.point.up.right.fill" }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf, png

    var id: String { rawValue }
    var displayName: String { rawValue.uppercased() }
}

struct GeneralSettingsView: View {
    @AppStorage(GeneralPrefs.language) private var languageRaw = AppLanguage.system.rawValue
    @AppStorage(GeneralPrefs.handedness) private var handednessRaw = Handedness.right.rawValue
    @AppStorage(GeneralPrefs.defaultExportFormat) private var exportFormatRaw = ExportFormat.pdf.rawValue
    @AppStorage(LayoutPrefs.showDates) private var showDates = true

    @State private var didResetOnboarding = false

    var body: some View {
        Form {
            Section("Card Display") {
                Toggle("Show edited dates on cards", isOn: $showDates)
            }

            Section {
                Picker("App Language", selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
            } footer: {
                Text("There's no translated string catalog yet, so UI text stays in English. This does change the locale used for dates and numbers app-wide.")
                    .font(.caption)
            }

            Section {
                Picker("Toolbar Side", selection: $handednessRaw) {
                    ForEach(Handedness.allCases) { hand in
                        Label(hand.displayName, systemImage: hand.systemImage).tag(hand.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Handedness")
            } footer: {
                UnwiredNote("The notepad toolbar keeps Home/Sidebar/Title on the left and the pencil/tool palette on the right regardless of this setting.")
            }

            Section {
                Picker("Default Export Format", selection: $exportFormatRaw) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.displayName).tag(format.rawValue)
                    }
                }
            } header: {
                Text("Export")
            } footer: {
                Text("Used by the Export button (square-and-arrow-up icon) in a notepad's toolbar.")
                    .font(.caption)
            }

            Section {
                Button(role: .destructive) {
                    UserDefaults.standard.set(false, forKey: "onboarding.completed")
                    didResetOnboarding = true
                } label: {
                    Label("Reset Onboarding Tutorial", systemImage: "arrow.counterclockwise")
                }
                if didResetOnboarding {
                    Label("The welcome tutorial will show again once you close Settings.", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("General")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack { GeneralSettingsView() }
}
