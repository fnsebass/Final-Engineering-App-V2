//
//  SyncSettingsView.swift
//  Tolerance
//
//  iCloud sync toggle (mirrors the SwiftData store to the user's private
//  CloudKit database — see engineering_app_1App.makeContainer()) and manual
//  backup export/restore (see BackupService). Both exist so deleting the
//  app doesn't have to mean losing everything: iCloud syncs automatically,
//  manual backup is a one-off safety net you control yourself.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    @Environment(\.modelContext) private var modelContext

    @AppStorage("settings.sync.engine") private var syncEngineRaw = SyncEngine.none.rawValue
    @AppStorage("settings.sync.icloudEnabled") private var icloudEnabled = false
    @AppStorage("settings.sync.autoSync") private var autoSync = false
    @AppStorage("settings.sync.conflictResolution") private var conflictResolutionRaw = ConflictResolution.askEachTime.rawValue

    @State private var exportedFileURL: URL?
    @State private var showExportShare = false
    @State private var exportError: String?
    @State private var isExporting = false

    @State private var showRestoreImporter = false
    @State private var showRestoreStagedAlert = false
    @State private var restoreError: String?

    var body: some View {
        Form {
            Section {
                Toggle("iCloud Sync", isOn: $icloudEnabled)
                    .onChange(of: icloudEnabled) { _, enabled in
                        syncEngineRaw = enabled ? SyncEngine.iCloud.rawValue : SyncEngine.none.rawValue
                    }
                Toggle("Auto-Sync", isOn: $autoSync)
                    .disabled(!icloudEnabled)
            } header: {
                Text("Cloud Storage")
            } footer: {
                Text(icloudEnabled
                     ? "Takes effect next launch — close the app completely and reopen it. Notes will mirror to your private iCloud database, so deleting and reinstalling the app restores them automatically. Google Drive and WebDAV aren't implemented yet."
                     : "Notepads are stored on this device only right now — deleting the app deletes them permanently. Turning this on mirrors everything to your private iCloud database instead.")
                    .font(.caption)
            }

            Section {
                Button {
                    exportBackup()
                } label: {
                    if isExporting {
                        HStack {
                            ProgressView()
                            Text("Preparing Backup…")
                        }
                    } else {
                        Label("Export Backup", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isExporting)
                if let exportError {
                    Text(exportError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Manual Backup")
            } footer: {
                Text("Saves everything on this device — notes, books, and diagrams — to a single file you keep yourself, in Files, iCloud Drive, or wherever you like.")
                    .font(.caption)
            }

            Section {
                Button {
                    showRestoreImporter = true
                } label: {
                    Label("Restore from Backup", systemImage: "square.and.arrow.down")
                }
                if let restoreError {
                    Text(restoreError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Replaces everything currently on this device with the backup you pick. Requires restarting the app to finish.")
                    .font(.caption)
            }

            Section {
                Picker("File Conflict Resolution", selection: $conflictResolutionRaw) {
                    ForEach(ConflictResolution.allCases) { rule in
                        Text(rule.displayName).tag(rule.rawValue)
                    }
                }
            } footer: {
                UnwiredNote("Only matters once iCloud has synced changes from two devices at once — that merge logic isn't wired up yet, so the most recent save quietly wins for now.")
            }
        }
        .navigationTitle("Sync")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showExportShare) {
            if let exportedFileURL {
                BackupShareSheet(activityItems: [exportedFileURL])
            }
        }
        #endif
        .fileImporter(isPresented: $showRestoreImporter, allowedContentTypes: [.data]) { result in
            handleRestorePick(result)
        }
        .alert("Restore Staged", isPresented: $showRestoreStagedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Close the app completely (swipe it away in the App Switcher) and reopen it to finish restoring. Anything on this device not in the backup will be replaced.")
        }
    }

    private func exportBackup() {
        exportError = nil
        guard let storeURL = BackupService.liveStoreURL else {
            exportError = "Couldn't locate the notes database."
            return
        }
        try? modelContext.save()
        isExporting = true
        Task.detached(priority: .userInitiated) {
            do {
                let url = try BackupService.exportBackup(storeURL: storeURL)
                await MainActor.run {
                    exportedFileURL = url
                    isExporting = false
                    showExportShare = true
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }

    private func handleRestorePick(_ result: Result<URL, Error>) {
        restoreError = nil
        switch result {
        case .success(let url):
            do {
                try BackupService.stageRestore(from: url)
                showRestoreStagedAlert = true
            } catch {
                restoreError = error.localizedDescription
            }
        case .failure(let error):
            restoreError = error.localizedDescription
        }
    }
}

#if os(iOS)
private struct BackupShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        // On iPad, UIActivityViewController can fail to appear at all unless
        // its popover has an anchor — even when presented inside a SwiftUI
        // .sheet(), some iPadOS versions still route it through a popover
        // presentation controller internally.
        if let popover = controller.popoverPresentationController, let window = Self.keyWindow() {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
#endif

#Preview {
    NavigationStack { SyncSettingsView() }
}
