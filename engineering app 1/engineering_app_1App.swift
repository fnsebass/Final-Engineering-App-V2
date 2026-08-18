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
struct ToleranceApp: App {
    var sharedModelContainer: ModelContainer = ToleranceApp.makeContainer()

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(sharedModelContainer)
    }

    /// Builds the model container. If the on-disk store can't be opened or
    /// migrated (e.g. after a schema change during development), the old store
    /// is deleted and recreated so the app never gets stuck in a crash loop.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Notepad.self, Page.self, Folder.self])
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
