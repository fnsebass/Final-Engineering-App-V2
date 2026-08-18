//
//  LayoutSettingsView.swift
//  Tolerance
//
//  Preferences for how the home sidebar looks. Opened from the settings box at
//  the bottom of the sidebar. Stored in UserDefaults via @AppStorage.
//

import SwiftUI

/// Keys shared with HomeView.
enum LayoutPrefs {
    static let showDates = "layout.showDates"
    static let foldersFirst = "layout.foldersFirst"
    static let accentRaw = "layout.accent"
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
    @AppStorage(LayoutPrefs.showDates) private var showDates = true
    @AppStorage(LayoutPrefs.foldersFirst) private var foldersFirst = true
    @AppStorage(LayoutPrefs.accentRaw) private var accentRaw = LayoutAccent.blue.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Sidebar") {
                    Toggle("Show edited dates", isOn: $showDates)
                    Toggle("List folders first", isOn: $foldersFirst)
                }
                Section("Accent color") {
                    Picker("Accent", selection: $accentRaw) {
                        ForEach(LayoutAccent.allCases) { accent in
                            HStack {
                                Circle().fill(accent.color).frame(width: 16, height: 16)
                                Text(accent.rawValue.capitalized)
                            }
                            .tag(accent.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Customize Layout")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .frame(minWidth: 320, minHeight: 380)
    }
}
