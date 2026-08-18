//
//  HomeView.swift
//  Tolerance
//
//  Home screen. A sidebar lists and sorts all notepads and hosts the
//  "New Notepad" button; selecting a notepad opens it in the detail area and
//  collapses the sidebar so the canvas gets the full screen.
//

import SwiftUI
import SwiftData

enum NotepadSort: String, CaseIterable, Identifiable {
    case lastEdited = "Last edited"
    case created = "Date created"
    case title = "Name"
    var id: String { rawValue }
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var notepads: [Notepad]

    @State private var selection: Notepad?
    @State private var sort: NotepadSort = .lastEdited
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @State private var renameTarget: Notepad?
    @State private var renameText = ""

    private var sortedNotepads: [Notepad] {
        switch sort {
        case .lastEdited: return notepads.sorted { $0.lastEditedDate > $1.lastEditedDate }
        case .created: return notepads.sorted { $0.createdDate > $1.createdDate }
        case .title: return notepads.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            if let selection {
                NotepadEditorView(notepad: selection)
                    .id(selection.persistentModelID)
            } else {
                ContentUnavailableView("Select a Notepad",
                                       systemImage: "sidebar.left",
                                       description: Text("Choose a notepad on the left, or create a new one."))
            }
        }
        .onChange(of: selection) { _, newValue in
            // Collapse the sidebar when a notepad is opened.
            if newValue != nil {
                withAnimation { columnVisibility = .detailOnly }
            }
        }
        .alert("Rename Notepad", isPresented: renameBinding) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") { commitRename() }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Button(action: createNotepad) {
                    Label("New Notepad", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
            }

            Section("Sort by") {
                Picker("Sort by", selection: $sort) {
                    ForEach(NotepadSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Section("Notepads") {
                if sortedNotepads.isEmpty {
                    Text("No notepads yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedNotepads) { notepad in
                        NavigationLink(value: notepad) {
                            NotepadRow(notepad: notepad)
                        }
                        .contextMenu {
                            Button { beginRename(notepad) } label: { Label("Rename", systemImage: "pencil") }
                            Button(role: .destructive) { delete(notepad) } label: { Label("Delete", systemImage: "trash") }
                        }
                        .swipeActions {
                            Button(role: .destructive) { delete(notepad) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    .onDelete(perform: deleteAtOffsets)
                }
            }
        }
        .navigationTitle("Tolerance")
    }

    // MARK: - Actions

    private func createNotepad() {
        let notepad = Notepad()
        modelContext.insert(notepad)
        let firstPage = Page(pageIndex: 0)
        firstPage.notepad = notepad
        modelContext.insert(firstPage)
        selection = notepad
    }

    private func delete(_ notepad: Notepad) {
        if selection == notepad { selection = nil }
        modelContext.delete(notepad)
    }

    private func deleteAtOffsets(_ offsets: IndexSet) {
        for index in offsets { delete(sortedNotepads[index]) }
    }

    private func beginRename(_ notepad: Notepad) {
        renameTarget = notepad
        renameText = notepad.title
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        target.title = trimmed.isEmpty ? "Untitled Notepad" : trimmed
        target.markEdited()
        renameTarget = nil
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }
}

private struct NotepadRow: View {
    let notepad: Notepad
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(notepad.title).lineLimit(1)
                Text(notepad.lastEditedDate, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Notepad.self, Page.self], inMemory: true)
}
