//
//  SyncSettingsView.swift
//  Tolerance
//
//  Cloud storage engine, auto-sync, local backup export, and conflict
//  resolution. The app stores everything in an on-device SwiftData store
//  only (see engineering_app_1App.swift) — there is no cloud sync engine
//  yet — so these are saved preferences for a future sync implementation.
//

import SwiftUI

enum SyncEngine: String, CaseIterable, Identifiable {
    case none, iCloud, googleDrive, webDAV
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:        return "None (Local Only)"
        case .iCloud:       return "iCloud"
        case .googleDrive:  return "Google Drive"
        case .webDAV:       return "WebDAV"
        }
    }
}

enum ConflictResolution: String, CaseIterable, Identifiable {
    case keepMine, keepCloud, askEachTime
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .keepMine:     return "Keep This Device's Copy"
        case .keepCloud:    return "Keep Cloud Copy"
        case .askEachTime:  return "Ask Each Time"
        }
    }
}

struct SyncSettingsView: View {
    @AppStorage("settings.sync.engine") private var syncEngineRaw = SyncEngine.none.rawValue
    @AppStorage("settings.sync.autoSync") private var autoSync = false
    @AppStorage("settings.sync.conflictResolution") private var conflictResolutionRaw = ConflictResolution.askEachTime.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Cloud Storage Engine", selection: $syncEngineRaw) {
                    ForEach(SyncEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine.rawValue)
                    }
                }
                Toggle("Auto-Sync", isOn: $autoSync)
                    .disabled(syncEngineRaw == SyncEngine.none.rawValue)
            } footer: {
                UnwiredNote("Notepads are stored locally on this device only; no cloud sync engine is connected yet.")
            }

            Section {
                Label("Export Local Backup", systemImage: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
            } footer: {
                UnwiredNote("There's no backup-export flow yet.")
            }

            Section {
                Picker("File Conflict Resolution", selection: $conflictResolutionRaw) {
                    ForEach(ConflictResolution.allCases) { rule in
                        Text(rule.displayName).tag(rule.rawValue)
                    }
                }
            } footer: {
                UnwiredNote("Only relevant once a sync engine is connected.")
            }
        }
        .navigationTitle("Sync")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack { SyncSettingsView() }
}
