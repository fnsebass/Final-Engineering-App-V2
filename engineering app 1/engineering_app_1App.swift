//
//  engineering_app_1App.swift
//  Tolerance
//
//  App entry point. Sets up the SwiftData model container for local, on-device
//  persistence (no cloud sync in v1).
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
                             TrussDiagram.self, CanvasPhoto.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

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
