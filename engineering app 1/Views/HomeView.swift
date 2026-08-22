//
//  HomeView.swift
//  Tolerance
//
//  Home screen implementation with updated SwiftData identifier bindings
//  and modernized Alert/Navigation patterns.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Lightweight payload for dragging a derivation onto a project folder.
struct NotepadDrag: Transferable, Codable {
    let id: PersistentIdentifier
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

enum SidebarSelection: Hashable {
    case loose
    case folder(PersistentIdentifier)
    case circuit(PersistentIdentifier)
    case fbd(PersistentIdentifier)
    case beam(PersistentIdentifier)
    case vectorField(PersistentIdentifier)
}

enum NotepadSort: String, CaseIterable, Identifiable {
    case lastEdited = "Last edited"
    case created    = "Date created"
    case title      = "Name"
    var id: String { rawValue }
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var notepads: [Notepad]
    @Query private var folders: [Folder]
    @Query(sort: \CircuitDiagram.createdDate,     order: .reverse) private var circuits:     [CircuitDiagram]
    @Query(sort: \FBDDiagram.createdDate,         order: .reverse) private var fbds:         [FBDDiagram]
    @Query(sort: \BeamDiagram.createdDate,        order: .reverse) private var beams:        [BeamDiagram]
    @Query(sort: \VectorFieldDiagram.createdDate, order: .reverse) private var vectorFields: [VectorFieldDiagram]

    @State private var selection: SidebarSelection? = .loose
    @State private var openNotepadID: PersistentIdentifier?
    @State private var sort: NotepadSort = .lastEdited
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @State private var showLayoutSettings = false
    @State private var showHandwritingMemory = false
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    
    @State private var renameTarget: Notepad?
    @State private var renameText = ""
    @State private var showRenameAlert = false
    @State private var folderRenameTarget: Folder?
    @State private var folderRenameText = ""
    @State private var showFolderRenameAlert = false
    @State private var circuitRenameTarget: CircuitDiagram?
    @State private var circuitRenameText = ""
    @State private var showCircuitRenameAlert = false
    @State private var fbdRenameTarget: FBDDiagram?
    @State private var fbdRenameText = ""
    @State private var showFBDRenameAlert = false
    @State private var beamRenameTarget: BeamDiagram?
    @State private var beamRenameText = ""
    @State private var showBeamRenameAlert = false
    @State private var vfRenameTarget: VectorFieldDiagram?
    @State private var vfRenameText = ""
    @State private var showVFRenameAlert = false

    @AppStorage(LayoutPrefs.showDates)         private var showDates          = true
    @AppStorage(LayoutPrefs.accentRaw)         private var accentRaw          = LayoutAccent.blue.rawValue
    @AppStorage(LayoutPrefs.defaultPaperStyle) private var defaultPaperStyleRaw = PaperStyle.grid.rawValue
    @AppStorage("isDarkMode")                 private var isDarkMode         = false

    private var accent: Color { LayoutAccent(rawValue: accentRaw)?.color ?? .blue }

    private var selectedFolder: Folder? {
        if case let .folder(id) = selection {
            return modelContext.model(for: id) as? Folder
        }
        return nil
    }

    private var openNotepad: Notepad? {
        guard let openNotepadID else { return nil }
        return modelContext.model(for: openNotepadID) as? Notepad
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
        .onChange(of: selection) { _, _ in openNotepadID = nil }
        .alert("New Project", isPresented: $showNewFolderAlert) {
            TextField("Project name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") { createFolder() }
        }
        .alert("Rename", isPresented: $showRenameAlert) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") { commitRename() }
        }
        .alert("Rename Project", isPresented: $showFolderRenameAlert) {
            TextField("Name", text: $folderRenameText)
            Button("Cancel", role: .cancel) { folderRenameTarget = nil }
            Button("Save") { commitFolderRename() }
        }
        .alert("Rename Circuit", isPresented: $showCircuitRenameAlert) {
            TextField("Name", text: $circuitRenameText)
            Button("Cancel", role: .cancel) { circuitRenameTarget = nil }
            Button("Save") { commitCircuitRename() }
        }
        .alert("Rename FBD", isPresented: $showFBDRenameAlert) {
            TextField("Name", text: $fbdRenameText)
            Button("Cancel", role: .cancel) { fbdRenameTarget = nil }
            Button("Save") { commitFBDRename() }
        }
        .alert("Rename Beam", isPresented: $showBeamRenameAlert) {
            TextField("Name", text: $beamRenameText)
            Button("Cancel", role: .cancel) { beamRenameTarget = nil }
            Button("Save") { commitBeamRename() }
        }
        .alert("Rename Vector Field", isPresented: $showVFRenameAlert) {
            TextField("Name", text: $vfRenameText)
            Button("Cancel", role: .cancel) { vfRenameTarget = nil }
            Button("Save") { commitVFRename() }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if case let .circuit(id) = selection,
           let circ = modelContext.model(for: id) as? CircuitDiagram {
            #if os(iOS)
            CircuitEditorView(diagram: circ, onBack: {
                withAnimation { selection = .loose; columnVisibility = .all }
            })
            .id(id)
            #endif
        } else if case let .fbd(id) = selection,
                  let fbd = modelContext.model(for: id) as? FBDDiagram {
            #if os(iOS)
            FBDEditorView(diagram: fbd, onBack: {
                withAnimation { selection = .loose; columnVisibility = .all }
            })
            .id(id)
            #endif
        } else if case let .beam(id) = selection,
                  let beam = modelContext.model(for: id) as? BeamDiagram {
            #if os(iOS)
            ShearBendingView(diagram: beam, onBack: {
                withAnimation { selection = .loose; columnVisibility = .all }
            })
            .id(id)
            #endif
        } else if case let .vectorField(id) = selection,
                  let vf = modelContext.model(for: id) as? VectorFieldDiagram {
            #if os(iOS)
            VectorFieldView(diagram: vf, onBack: {
                withAnimation { selection = .loose; columnVisibility = .all }
            })
            .id(id)
            #endif
        } else if let openNotepad {
            NotepadEditorView(notepad: openNotepad, onBack: closeNotepad)
                .id(openNotepad.persistentModelID)
        } else {
            NotepadGridView(
                title: selectedFolder?.name ?? "All Derivations",
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
                    Label("New Derivation", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)

                Button {
                    newFolderName = ""
                    showNewFolderAlert = true
                } label: {
                    Label("New Project", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.plain)

                Button(action: createCircuit) {
                    Label("New Circuit", systemImage: "bolt.circle.fill")
                }
                .buttonStyle(.plain)

                Button(action: createFBD) {
                    Label("New FBD", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                }
                .buttonStyle(.plain)

                Button(action: createBeam) {
                    Label("New Beam", systemImage: "chart.xyaxis.line")
                }
                .buttonStyle(.plain)

                Button(action: createVectorField) {
                    Label("New Vector Field", systemImage: "arrow.clockwise.circle.fill")
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

            Section("Workspace") {
                Label("All Derivations", systemImage: "tray.full")
                    .tag(SidebarSelection.loose)
                    .dropDestination(for: NotepadDrag.self) { items, _ in
                        setFolder(nil, for: items)
                        return true
                    }

                ForEach(folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { folder in
                    Label("\(folder.name) (\(folder.notepads.count))", systemImage: "folder")
                        .tag(SidebarSelection.folder(folder.persistentModelID))
                        .dropDestination(for: NotepadDrag.self) { items, _ in
                            setFolder(folder, for: items)
                            return true
                        }
                        .contextMenu {
                            Button { beginFolderRename(folder) } label: { Label("Rename", systemImage: "pencil") }
                            Button(role: .destructive) { deleteFolder(folder) } label: { Label("Delete Project", systemImage: "trash") }
                        }
                }
                if folders.isEmpty {
                    Text("No projects yet — tap New Project, then drag derivations into it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Circuits") {
                ForEach(circuits) { circ in
                    Label(circ.title, systemImage: "bolt.circle.fill")
                        .tag(SidebarSelection.circuit(circ.persistentModelID))
                        .contextMenu {
                            Button { beginCircuitRename(circ) } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) { deleteCircuit(circ) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                if circuits.isEmpty {
                    Text("Tap New Circuit to start.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("FBD Diagrams") {
                ForEach(fbds) { fbd in
                    Label(fbd.title, systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                        .tag(SidebarSelection.fbd(fbd.persistentModelID))
                        .contextMenu {
                            Button { beginFBDRename(fbd) } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) { deleteFBD(fbd) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                if fbds.isEmpty {
                    Text("Tap New FBD to start.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Beam Diagrams") {
                ForEach(beams) { beam in
                    Label(beam.title, systemImage: "chart.xyaxis.line")
                        .tag(SidebarSelection.beam(beam.persistentModelID))
                        .contextMenu {
                            Button { beginBeamRename(beam) } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) { deleteBeam(beam) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                if beams.isEmpty {
                    Text("Tap New Beam to start.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Vector Fields") {
                ForEach(vectorFields) { vf in
                    Label(vf.title, systemImage: "arrow.clockwise.circle.fill")
                        .tag(SidebarSelection.vectorField(vf.persistentModelID))
                        .contextMenu {
                            Button { beginVFRename(vf) } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) { deleteVF(vf) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                if vectorFields.isEmpty {
                    Text("Tap New Vector Field to start.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Derivation Notes")
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(isPresented: $showLayoutSettings) { LayoutSettingsView() }
        .sheet(isPresented: $showHandwritingMemory) {
            NavigationStack { HandwritingMemoryView() }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button { showLayoutSettings = true } label: {
                Label("Customize Layout", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            Divider().frame(height: 20)

            Button { showHandwritingMemory = true } label: {
                Image(systemName: "hand.draw")
                    .font(.system(size: 16))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Handwriting Memory")

            Divider().frame(height: 20)

            Button {
                withAnimation { isDarkMode.toggle() }
            } label: {
                Image(systemName: isDarkMode ? "moon.fill" : "sun.max")
                    .font(.system(size: 16))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(isDarkMode ? .blue : .orange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDarkMode ? "Switch to light mode" : "Switch to dark mode")
        }
        .background(.bar)
    }

    // MARK: - Actions

    private func sorted(_ list: [Notepad]) -> [Notepad] {
        switch sort {
        case .lastEdited: return list.sorted { $0.lastEditedDate > $1.lastEditedDate }
        case .created:    return list.sorted { $0.createdDate > $1.createdDate }
        case .title:      return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private func createNotepad() {
        let notepad = Notepad()
        notepad.paperStyleRaw = defaultPaperStyleRaw
        notepad.folder = selectedFolder
        modelContext.insert(notepad)
        
        let firstPage = Page(pageIndex: 0)
        firstPage.notepad = notepad
        modelContext.insert(firstPage)
        
        open(notepad)
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        modelContext.insert(Folder(name: trimmed.isEmpty ? "New Project" : trimmed))
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
        openNotepadID = notepad.persistentModelID
        withAnimation { columnVisibility = .detailOnly }
    }

    private func closeNotepad() {
        openNotepadID = nil
        withAnimation { columnVisibility = .all }
    }

    private func delete(_ notepad: Notepad) {
        if openNotepadID == notepad.persistentModelID { openNotepadID = nil }
        modelContext.delete(notepad)
    }

    private func deleteFolder(_ folder: Folder) {
        if case let .folder(id) = selection, id == folder.persistentModelID {
            selection = .loose
        }
        modelContext.delete(folder)
    }

    private func beginRename(_ notepad: Notepad) {
        renameTarget = notepad
        renameText = notepad.title
        showRenameAlert = true
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        target.title = trimmed.isEmpty ? "New Derivation" : trimmed
        target.markEdited()
        renameTarget = nil
    }

    private func beginFolderRename(_ folder: Folder) {
        folderRenameTarget = folder
        folderRenameText = folder.name
        showFolderRenameAlert = true
    }

    private func commitFolderRename() {
        guard let target = folderRenameTarget else { return }
        let trimmed = folderRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        target.name = trimmed.isEmpty ? "New Project" : trimmed
        folderRenameTarget = nil
    }

    private func createCircuit() {
        let circuit = CircuitDiagram(title: "Circuit \(circuits.count + 1)")
        modelContext.insert(circuit)
        // Give SwiftData a tick to assign the persistent ID before selecting.
        DispatchQueue.main.async {
            selection = .circuit(circuit.persistentModelID)
            withAnimation { columnVisibility = .detailOnly }
        }
    }

    private func deleteCircuit(_ circuit: CircuitDiagram) {
        if case let .circuit(id) = selection, id == circuit.persistentModelID {
            selection = .loose
        }
        modelContext.delete(circuit)
    }

    private func beginCircuitRename(_ circuit: CircuitDiagram) {
        circuitRenameTarget = circuit
        circuitRenameText   = circuit.title
        showCircuitRenameAlert = true
    }

    private func commitCircuitRename() {
        guard let target = circuitRenameTarget else { return }
        let trimmed = circuitRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        target.title = trimmed.isEmpty ? "New Circuit" : trimmed
        circuitRenameTarget = nil
    }

    // MARK: - FBD CRUD

    private func createFBD() {
        let fbd = FBDDiagram(title: "FBD \(fbds.count + 1)")
        modelContext.insert(fbd)
        DispatchQueue.main.async {
            selection = .fbd(fbd.persistentModelID)
            withAnimation { columnVisibility = .detailOnly }
        }
    }

    private func deleteFBD(_ fbd: FBDDiagram) {
        if case let .fbd(id) = selection, id == fbd.persistentModelID { selection = .loose }
        modelContext.delete(fbd)
    }

    private func beginFBDRename(_ fbd: FBDDiagram) {
        fbdRenameTarget = fbd
        fbdRenameText   = fbd.title
        showFBDRenameAlert = true
    }

    private func commitFBDRename() {
        guard let target = fbdRenameTarget else { return }
        let trimmed = fbdRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        target.title = trimmed.isEmpty ? "New FBD" : trimmed
        fbdRenameTarget = nil
    }

    // MARK: - Beam CRUD

    private func createBeam() {
        let beam = BeamDiagram(title: "Beam \(beams.count + 1)")
        modelContext.insert(beam)
        DispatchQueue.main.async {
            selection = .beam(beam.persistentModelID)
            withAnimation { columnVisibility = .detailOnly }
        }
    }

    private func deleteBeam(_ beam: BeamDiagram) {
        if case let .beam(id) = selection, id == beam.persistentModelID { selection = .loose }
        modelContext.delete(beam)
    }

    private func beginBeamRename(_ beam: BeamDiagram) {
        beamRenameTarget = beam
        beamRenameText   = beam.title
        showBeamRenameAlert = true
    }

    private func commitBeamRename() {
        guard let target = beamRenameTarget else { return }
        let trimmed = beamRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        target.title = trimmed.isEmpty ? "New Beam" : trimmed
        beamRenameTarget = nil
    }

    // MARK: - Vector Field CRUD

    private func createVectorField() {
        let vf = VectorFieldDiagram(title: "Field \(vectorFields.count + 1)")
        modelContext.insert(vf)
        DispatchQueue.main.async {
            selection = .vectorField(vf.persistentModelID)
            withAnimation { columnVisibility = .detailOnly }
        }
    }

    private func deleteVF(_ vf: VectorFieldDiagram) {
        if case let .vectorField(id) = selection, id == vf.persistentModelID { selection = .loose }
        modelContext.delete(vf)
    }

    private func beginVFRename(_ vf: VectorFieldDiagram) {
        vfRenameTarget = vf
        vfRenameText   = vf.title
        showVFRenameAlert = true
    }

    private func commitVFRename() {
        guard let target = vfRenameTarget else { return }
        let trimmed = vfRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        target.title = trimmed.isEmpty ? "New Vector Field" : trimmed
        vfRenameTarget = nil
    }
}

// MARK: - Grid View & Card Components

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
                    Label("No Derivations", systemImage: "doc")
                } description: {
                    Text("Tap + to start a new derivation.")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(notepads) { notepad in
                            Button { onOpen(notepad) } label: {
                                NotepadCard(notepad: notepad, showDate: showDates)
                            }
                            .buttonStyle(.plain)
                            .draggable(NotepadDrag(id: notepad.persistentModelID))
                            .contextMenu {
                                Button { onRename(notepad) } label: { Label("Rename", systemImage: "pencil") }
                                if isInFolder {
                                    Button { onRemoveFromFolder(notepad) } label: {
                                        Label("Remove from Project", systemImage: "folder.badge.minus")
                                    }
                                }
                                Button(role: .destructive) { onDelete(notepad) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
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
                Button(action: onNew) { Label("New Derivation", systemImage: "plus") }
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
                .overlay(Image(systemName: "function").font(.system(size: 36)).foregroundStyle(.tint))
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
        .modelContainer(for: [Notepad.self, Page.self, Folder.self, CircuitDiagram.self,
                               FBDDiagram.self, BeamDiagram.self, VectorFieldDiagram.self],
                        inMemory: true)
}
