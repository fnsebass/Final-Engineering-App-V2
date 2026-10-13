//
//  engineering_app_1App.swift
//  Tolerance
//
//  App entry point. Sets up the SwiftData model container for local, on-device
//  persistence, optionally mirrored to the user's private iCloud database
//  (Settings → Sync → iCloud Sync — see SyncSettingsView). Also applies any
//  backup staged by BackupService.stageRestore(from:) before the container
//  opens, since a restore replaces the store files on disk and that can only
//  safely happen while nothing has them open yet.
//

import SwiftUI
import SwiftData

@main
struct DerivationNotesApp: App {
    var sharedModelContainer: ModelContainer = DerivationNotesApp.makeContainer()
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("settings.theme.interfaceScale") private var interfaceScale = 1.0
    @AppStorage(GeneralPrefs.language) private var languageRaw = AppLanguage.system.rawValue

    /// Settings → General → App Language. There's no translated string catalog
    /// yet, so this only overrides the locale used for built-in date/number
    /// formatting (e.g. notepad card dates) rather than any UI text.
    private var localeOverride: Locale? {
        switch AppLanguage(rawValue: languageRaw) ?? .system {
        case .system: return nil
        case .english: return Locale(identifier: "en")
        case .spanish: return Locale(identifier: "es")
        case .french:  return Locale(identifier: "fr")
        case .german:  return Locale(identifier: "de")
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(isDarkMode ? .dark : .light)
                .dynamicTypeSize(InterfaceScale.dynamicTypeSize(for: interfaceScale))
                .environment(\.locale, localeOverride ?? Locale.autoupdatingCurrent)
        }
        .modelContainer(sharedModelContainer)
    }

    /// Builds the model container. If the on-disk store can't be opened or
    /// migrated (e.g. after a schema change during development), the old store
    /// is deleted and recreated so the app never gets stuck in a crash loop.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Notepad.self, Page.self, Folder.self, Chapter.self, HandwritingCorrection.self,
                             CircuitDiagram.self, FBDDiagram.self, BeamDiagram.self, VectorFieldDiagram.self,
                             TrussDiagram.self, CanvasPhoto.self, AIPracticeQuestion.self,
                             GradeClass.self, GradeCategory.self, GradeAssignment.self])

        // Settings → Sync → iCloud Sync. Stored directly in UserDefaults (not
        // @AppStorage) since this runs before any View exists. Takes effect
        // on next launch — SwiftData's container is fixed for the app's
        // lifetime, so toggling the setting mid-session can't hot-swap it.
        let defaults = UserDefaults.standard
        let icloudEnabledKey = "settings.sync.icloudEnabled"
        let icloudEnabled = defaults.bool(forKey: icloudEnabledKey)

        // Only used to locate/migrate the on-disk store and to resolve any
        // staged restore below — independent of whether iCloud is on, since
        // SwiftData assigns the same default file location either way.
        let localProbe = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        BackupService.applyPendingRestoreIfNeeded(storeURL: localProbe.url)
        BackupService.liveStoreURL = localProbe.url

        if icloudEnabled {
            // CloudKit setup can get stuck in ways that never throw a
            // catchable Swift error — seen in practice as a flood of
            // "MDB_MAP_FULL" errors from its on-device cache, especially on
            // the Simulator, which can hang launch indefinitely rather than
            // fail. Bounding how long we wait means launch can never hang
            // forever regardless of cause.
            let cloudConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
            if let container = containerWithTimeout(schema: schema, configuration: cloudConfiguration, timeout: 5) {
                return container
            }
            // Timed out or failed — don't keep retrying (and hanging) every
            // launch; fall back to local-only until the user re-enables it.
            defaults.set(false, forKey: icloudEnabledKey)
        }

        return localContainer(schema: schema, configuration: localProbe)
    }

    /// Runs container creation on a background thread and gives up waiting
    /// after `timeout` seconds — if it eventually finishes anyway, the
    /// result is simply discarded, which is a safe trade next to the
    /// alternative of launch hanging forever.
    private static func containerWithTimeout(schema: Schema, configuration: ModelConfiguration,
                                             timeout: TimeInterval) -> ModelContainer? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: ModelContainer?
        let thread = Thread {
            result = try? ModelContainer(for: schema, configurations: [configuration])
            semaphore.signal()
        }
        thread.start()
        _ = semaphore.wait(timeout: .now() + timeout)
        return result
    }

    private static func localContainer(schema: Schema, configuration: ModelConfiguration) -> ModelContainer {
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Migration/open failed — remove the store files and try once more.
            removeStoreFiles(at: configuration.url)
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                // Last resort: run in memory so the app still launches.
                let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try! ModelContainer(for: schema, configurations: [memory])
            }
        }
    }

    private static func removeStoreFiles(at url: URL) {
        let fileManager = FileManager.default
        let base = url.deletingPathExtension().lastPathComponent
        let directory = url.deletingLastPathComponent()
        // Remove the store plus its -shm / -wal sidecar files.
        for suffix in ["store", "store-shm", "store-wal"] {
            try? fileManager.removeItem(at: directory.appendingPathComponent("\(base).\(suffix)"))
        }
        try? fileManager.removeItem(at: url)
    }
}
