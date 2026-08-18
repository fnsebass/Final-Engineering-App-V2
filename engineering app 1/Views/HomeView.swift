//
//  HomeView.swift
//  Tolerance
//
//  Home screen. The sidebar holds folders (plus "All Notepads") and the
//  New Notepad / New Folder buttons and a bottom "Customize Layout" box. The
//  larger detail panel shows a grid of the selected container's notepads:
//  "All Notepads" shows loose notepads; a folder shows only its own. Opening a
//  notepad replaces the grid with the editor.
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

/// What the sidebar has selected, which drives the detail grid.
enum SidebarSelection: Hashable {
    case loose
    case folder(PersistentIdentifier)
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

    @State private var selection: SidebarSelection? = .loose
    @State private var openNotepad: Notepad?
    @State private var sort: NotepadSort = .lastEdited
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @State private var showLayoutSettings = false
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var renameTarget: Notepad?
    @State private var renameText = ""
    @State private var folderRenameTarget: Folder?
    @State private var folderRenameText = ""

    @AppStorage(LayoutPrefs.showDates) private var showDates = true
    @AppStorage(LayoutPrefs.accentRaw) private var accentRaw = LayoutAccent.blue.rawValue

    private var accent: Color { LayoutAccent(rawValue: accentRaw)?.color ?? .blue }

    private var selectedFolder: Folder? {
        if case let .folder(id) = selection { return modelContext.model(for: id) as? Folder }
        return nil
    }

    private var containerNotepads: [Notepad] {
        let list = selectedFolder?.notepads ?? notepads.filter { $0.folder == nil }
        return sorted(list)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .tint(accent)
        .onChange(of: selection) { _, _ in openNotepad = nil }
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

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let openNotepad {
            NotepadEditorView(notepad: openNotepad, onBack: closeNotepad)
                .id(openNotepad.persistentModelID)
        } else {
            NotepadGridView(
                title: selectedFolder?.name ?? "All Notepads",
                notepads: containerNotepads,
                showDates: showDates,
                isInFolder: selectedFolder != nil,
                onOpen: open,
                onNew: createNotepad,
                onRename: beginRename,
                onDelete: delete,
                onRemoveFromFolder: { $0.folder = nil }
            )
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

            Section("Library") {
                Label("All Notepads", systemImage: "tray.full")
                    .tag(SidebarSelection.loose)
                    .dropDestination(for: NotepadDrag.self) { items, _ in
                        setFolder(nil, for: items); return true
                    }

                ForEach(folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { folder in
                    Label("\(folder.name)  (\(folder.notepads.count))", systemImage: "folder")
                        .tag(SidebarSelection.folder(folder.persistentModelID))
                        .dropDestination(for: NotepadDrag.self) { items, _ in
                            setFolder(folder, for: items); return true
                        }
                        .contextMenu {
                            Button { beginFolderRename(folder) } label: { Label("Rename", systemImage: "pencil") }
                            Button(role: .destructive) { deleteFolder(folder) } label: { Label("Delete Folder", systemImage: "trash") }
                        }
                }
                if folders.isEmpty {
                    Text("No folders yet — tap New Folder, then drag notepads onto it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Tolerance")
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(isPresented: $showLayoutSettings) { LayoutSettingsView() }
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
        notepad.folder = selectedFolder // create inside the current folder, if any
        modelContext.insert(notepad)
        let firstPage = Page(pageIndex: 0)
        firstPage.notepad = notepad
        modelContext.insert(firstPage)
        open(notepad)
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        modelContext.insert(Folder(name: trimmed.isEmpty ? "New Folder" : trimmed))
        newFolderName = ""
    }

    private func setFolder(_ folder: Folder?, for items: [NotepadDrag]) {
        for item in items {
            if let notepad = modelContext.model(for: item.id) as? Notepad {
                notepad.folder = folder
            }
        }
    }

    private func open(_ notepad: Notepad) {
        openNotepad = notepad
        withAnimation { columnVisibility = .detailOnly }
    }

    private func closeNotepad() {
        openNotepad = nil
        withAnimation { columnVisibility = .all }
    }

    private func delete(_ notepad: Notepad) {
        if openNotepad == notepad { openNotepad = nil }
        modelContext.delete(notepad)
    }

    private func deleteFolder(_ folder: Folder) {
        if case let .folder(id) = selection, id == folder.persistentModelID { selection = .loose }
        modelContext.delete(folder) // notepads become loose (nullify)
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

// MARK: - Grid

private struct NotepadGridView: View {
    let title: String
    let notepads: [Notepad]
    let showDates: Bool
    let isInFolder: Bool
    let onOpen: (Notepad) -> Void
    let onNew: () -> Void
    let onRename: (Notepad) -> Void
    let onDelete: (Notepad) -> Void
    let onRemoveFromFolder: (Notepad) -> Void

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 20)]

    var body: some View {
        Group {
            if notepads.isEmpty {
                ContentUnavailableView {
                    Label("No Notepads", systemImage: "doc")
                } description: {
                    Text("Tap the + button to create one.")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(notepads) { notepad in
                            Button { onOpen(notepad) } label: { NotepadCard(notepad: notepad, showDate: showDates) }
                                .buttonStyle(.plain)
                                .draggable(NotepadDrag(id: notepad.persistentModelID))
                                .contextMenu {
                                    Button { onRename(notepad) } label: { Label("Rename", systemImage: "pencil") }
                                    if isInFolder {
                                        Button { onRemoveFromFolder(notepad) } label: { Label("Remove from Folder", systemImage: "folder.badge.minus") }
                                    }
                                    Button(role: .destructive) { onDelete(notepad) } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onNew) { Label("New Notepad", systemImage: "plus") }
            }
        }
    }
}

private struct NotepadCard: View {
    let notepad: Notepad
    let showDate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .frame(height: 150)
                .overlay(Image(systemName: "doc.text").font(.system(size: 40)).foregroundStyle(.tint))
                .overlay(alignment: .bottomTrailing) {
                    Text("\(notepad.pages.count) pg")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                        .padding(8)
                }
            Text(notepad.title).font(.headline).lineLimit(1)
            if showDate {
                Text(notepad.lastEditedDate, format: .relative(presentation: .named))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Notepad.self, Page.self, Folder.self], inMemory: true)
}
