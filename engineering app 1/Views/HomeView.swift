//
//  HomeView.swift
//  Tolerance
//
//  Home screen. A sidebar sorts notepads, groups them into folders (drag a
//  notepad onto a folder to file it), and hosts New Notepad / New Folder
//  buttons plus a "Customize Layout" settings box pinned to the bottom.
//  Selecting or creating a notepad opens it in the larger detail panel.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Lightweight payload for dragging a notepad onto a folder.
struct NotepadDrag: Transferable, Codable {
    let id: PersistentIdentifier
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

enum NotepadSort: String, CaseIterable, Identifiable {
    case lastEdited = "Last edited"
    case created = "Date created"
    case title = "Name"
    var id: String { rawValue }
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var notepads: [Notepad]
    @Query private var folders: [Folder]

    @State private var selection: Notepad?
    @State private var sort: NotepadSort = .lastEdited
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // Sheets / alerts.
    @State private var showLayoutSettings = false
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var renameTarget: Notepad?
    @State private var renameText = ""
    @State private var folderRenameTarget: Folder?
    @State private var folderRenameText = ""

    // Layout prefs.
    @AppStorage(LayoutPrefs.showDates) private var showDates = true
    @AppStorage(LayoutPrefs.foldersFirst) private var foldersFirst = true
    @AppStorage(LayoutPrefs.accentRaw) private var accentRaw = LayoutAccent.blue.rawValue

    private var accent: Color {
        LayoutAccent(rawValue: accentRaw)?.color ?? .blue
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            if let selection {
                NotepadEditorView(notepad: selection, onBack: goBack)
                    .id(selection.persistentModelID)
            } else {
                ContentUnavailableView("Select a Notepad",
                                       systemImage: "sidebar.left",
                                       description: Text("Choose a notepad on the left, or create a new one."))
            }
        }
        .tint(accent)
        .onChange(of: selection) { _, newValue in
            if newValue != nil { withAnimation { columnVisibility = .detailOnly } }
        }
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") { createFolder() }
        }
        .alert("Rename Notepad", isPresented: renameBinding) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") { commitRename() }
        }
        .alert("Rename Folder", isPresented: folderRenameBinding) {
            TextField("Name", text: $folderRenameText)
            Button("Cancel", role: .cancel) { folderRenameTarget = nil }
            Button("Save") { commitFolderRename() }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Button(action: createNotepad) {
                    Label("New Notepad", systemImage: "plus.circle.fill").font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                Button { newFolderName = ""; showNewFolderAlert = true } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
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

            if foldersFirst {
                foldersSection
                looseSection
            } else {
                looseSection
                foldersSection
            }
        }
        .navigationTitle("Tolerance")
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(isPresented: $showLayoutSettings) { LayoutSettingsView() }
    }

    private var foldersSection: some View {
        Section("Folders") {
            if folders.isEmpty {
                Text("No folders yet — tap New Folder, then drag notepads in.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { folder in
                DisclosureGroup {
                    ForEach(sorted(folder.notepads)) { notepad in
                        notepadRow(notepad)
                    }
                } label: {
                    Label("\(folder.name)  (\(folder.notepads.count))", systemImage: "folder")
                        .contextMenu {
                            Button { beginFolderRename(folder) } label: { Label("Rename", systemImage: "pencil") }
                            Button(role: .destructive) { modelContext.delete(folder) } label: { Label("Delete Folder", systemImage: "trash") }
                        }
                        .dropDestination(for: NotepadDrag.self) { items, _ in
                            fileNotepads(items, into: folder)
                            return true
                        }
                }
            }
        }
    }

    private var looseSection: some View {
        Section("Notepads") {
            let loose = sorted(notepads.filter { $0.folder == nil })
            if loose.isEmpty {
                Text("No loose notepads.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(loose) { notepad in
                notepadRow(notepad)
            }
        }
    }

    private func notepadRow(_ notepad: Notepad) -> some View {
        NavigationLink(value: notepad) {
            NotepadRow(notepad: notepad, showDate: showDates)
        }
        .draggable(NotepadDrag(id: notepad.persistentModelID))
        .contextMenu {
            Button { beginRename(notepad) } label: { Label("Rename", systemImage: "pencil") }
            if notepad.folder != nil {
                Button { notepad.folder = nil } label: { Label("Remove from Folder", systemImage: "folder.badge.minus") }
            }
            Button(role: .destructive) { delete(notepad) } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions {
            Button(role: .destructive) { delete(notepad) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var bottomBar: some View {
        Button { showLayoutSettings = true } label: {
            Label("Customize Layout", systemImage: "slider.horizontal.3")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(.bar)
    }

    // MARK: - Actions

    private func sorted(_ list: [Notepad]) -> [Notepad] {
        switch sort {
        case .lastEdited: return list.sorted { $0.lastEditedDate > $1.lastEditedDate }
        case .created: return list.sorted { $0.createdDate > $1.createdDate }
        case .title: return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private func createNotepad() {
        let notepad = Notepad()
        modelContext.insert(notepad)
        let firstPage = Page(pageIndex: 0)
        firstPage.notepad = notepad
        modelContext.insert(firstPage)
        selection = notepad // opens in the middle detail panel
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = Folder(name: trimmed.isEmpty ? "New Folder" : trimmed)
        modelContext.insert(folder)
        newFolderName = ""
    }

    private func fileNotepads(_ items: [NotepadDrag], into folder: Folder) {
        for item in items {
            if let notepad = modelContext.model(for: item.id) as? Notepad {
                notepad.folder = folder
            }
        }
    }

    private func delete(_ notepad: Notepad) {
        if selection == notepad { selection = nil }
        modelContext.delete(notepad)
    }

    private func goBack() {
        selection = nil
        withAnimation { columnVisibility = .all }
    }

    private func beginRename(_ notepad: Notepad) { renameTarget = notepad; renameText = notepad.title }
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

    private func beginFolderRename(_ folder: Folder) { folderRenameTarget = folder; folderRenameText = folder.name }
    private func commitFolderRename() {
        guard let target = folderRenameTarget else { return }
        let trimmed = folderRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        target.name = trimmed.isEmpty ? "New Folder" : trimmed
        folderRenameTarget = nil
    }
    private var folderRenameBinding: Binding<Bool> {
        Binding(get: { folderRenameTarget != nil }, set: { if !$0 { folderRenameTarget = nil } })
    }
}

private struct NotepadRow: View {
    let notepad: Notepad
    let showDate: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(notepad.title).lineLimit(1)
                if showDate {
                    Text(notepad.lastEditedDate, format: .relative(presentation: .named))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Notepad.self, Page.self, Folder.self], inMemory: true)
}
