//
//  ChapterMigrationService.swift
//  Tolerance
//
//  One-time backfill: every pre-existing book (Folder) that has notes but no
//  chapters yet gets a default "Chapter 1" holding all of its current notes,
//  so nothing becomes orphaned when the Chapter level is introduced.
//

import Foundation
import SwiftData

enum ChapterMigrationService {
    private static let completedKey = "migration.chapterV1.completed"

    static func runIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: completedKey) else { return }

        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        for folder in folders where folder.chapters.isEmpty && !folder.notepads.isEmpty {
            let chapter = Chapter(name: "Chapter 1")
            chapter.folder = folder
            context.insert(chapter)
            for notepad in folder.notepads {
                notepad.assign(to: chapter)
            }
        }

        UserDefaults.standard.set(true, forKey: completedKey)
    }
}
