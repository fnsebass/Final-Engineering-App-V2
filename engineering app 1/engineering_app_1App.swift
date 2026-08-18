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
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Notepad.self,
            Page.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(sharedModelContainer)
    }
}
