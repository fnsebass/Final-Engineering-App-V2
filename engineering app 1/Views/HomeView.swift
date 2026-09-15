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

/// Lightweight payload for dragging a note onto a book (folder).
struct NotepadDrag: Transferable, Codable {
    let id: PersistentIdentifier
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

enum SidebarSelection: Hashable {
    case loose
    case library
    case folder(PersistentIdentifier)
    case circuit(PersistentIdentifier)
    case fbd(PersistentIdentifier)
    case beam(PersistentIdentifier)
    case vectorField(PersistentIdentifier)
    case truss(PersistentIdentifier)
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
    @Query(sort: \TrussDiagram.createdDate,       order: .reverse) private var trusses:      [TrussDiagram]

    @State private var selection: SidebarSelection? = .loose
    // Holds the live model directly rather than a PersistentIdentifier — a
    // freshly-inserted object's identifier is temporary until SwiftData's
    // next autosave, and re-resolving it via modelContext.model(for:) on
    // every body re-render can crash with "model instance was invalidated"
    // once that temporary identifier is retired.
    @State private var openNotepad: Notepad?
    // Same rationale as openNotepad above — hold the live diagram objects
    // directly rather than re-resolving a PersistentIdentifier from
    // `selection` on every body re-render, which crashes with "model
    // instance was invalidated" once a freshly-created diagram's temporary
    // identifier is retired by SwiftData's next autosave.
    @State private var openCircuit: CircuitDiagram?
    @State private var openFBD: FBDDiagram?
    @State private var openBeam: BeamDiagram?
    @State private var openVectorField: VectorFieldDiagram?
    @State private var openTruss: TrussDiagram?
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
    @State private var trussRenameTarget: TrussDiagram?
    @State private var trussRenameText = ""
    @State private var showTrussRenameAlert = false

    // Notebook side panel (replaces the Home/Library list while in a book or note)
    @State private var canvasUndoManager: UndoManager? = nil
    @State private var pendingGraphRequest: String? = nil
    @State private var pendingGraphForce3D: Bool? = nil
    @State private var chapterRenameTarget: Chapter?
    @State private var chapterRenameText = ""
    @State private var showChapterRenameAlert = false

    // Sidebar expand state
    @State private var specialExpanded       = false
    @State private var otherProjectsExpanded = false
    @State private var circuitsExpanded      = true
    @State private var fbdsExpanded          = true
    @State private var beamsExpanded         = true
    @State private var vfsExpanded           = true
    @State private var trussesExpanded       = true

    @AppStorage(LayoutPrefs.showDates)         private var showDates          = true
    @AppStorage(LayoutPrefs.accentRaw)         private var accentRaw          = LayoutAccent.blue.rawValue
    @AppStorage(LayoutPrefs.defaultPaperStyle) private var defaultPaperStyleRaw = PaperStyle.grid.rawValue
    @AppStorage(LayoutPrefs.defaultPaperColorHex) private var defaultPaperColorHex = "#FFFFFF"
    @AppStorage("isDarkMode")                 private var isDarkMode         = false
    @AppStorage("settings.theme.oledBlack")   private var oledBlack          = false
    @AppStorage("onboarding.completed")       private var onboardingCompleted = false
    @State private var showOnboarding = false

    private var accent: Color { LayoutAccent(rawValue: accentRaw)?.color ?? .blue }

    private var selectedFolder: Folder? {
        if case let .folder(id) = selection {
            return modelContext.model(for: id) as? Folder
        }
        return nil
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .tint(accent)
        .onChange(of: selection) { _, new in
            openNotepad = nil
            // Resolve from the live @Query arrays (never a stale
            // PersistentIdentifier lookup) — but only overwrite when a match
            // is found, so a diagram set directly by create*() moments ago
            // isn't clobbered by a @Query that hasn't caught up yet.
            if case let .circuit(id) = new {
                if let f = circuits.first(where: { $0.persistentModelID == id }) { openCircuit = f }
            } else { openCircuit = nil }
            if case let .fbd(id) = new {
                if let f = fbds.first(where: { $0.persistentModelID == id }) { openFBD = f }
            } else { openFBD = nil }
            if case let .beam(id) = new {
                if let f = beams.first(where: { $0.persistentModelID == id }) { openBeam = f }
            } else { openBeam = nil }
            if case let .vectorField(id) = new {
                if let f = vectorFields.first(where: { $0.persistentModelID == id }) { openVectorField = f }
            } else { openVectorField = nil }
            if case let .truss(id) = new {
                if let f = trusses.first(where: { $0.persistentModelID == id }) { openTruss = f }
            } else { openTruss = nil }
        }
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
        .alert("Rename Truss", isPresented: $showTrussRenameAlert) {
            TextField("Name", text: $trussRenameText)
            Button("Cancel", role: .cancel) { trussRenameTarget = nil }
            Button("Save") { commitTrussRename() }
        }
        .alert("Rename Chapter", isPresented: $showChapterRenameAlert) {
            TextField("Name", text: $chapterRenameText)
            Button("Cancel", role: .cancel) { chapterRenameTarget = nil }
            Button("Save") { commitChapterRename() }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let openCircuit {
            #if os(iOS)
            CircuitEditorView(diagram: openCircuit, onBack: {
                withAnimation { selection = .loose; columnVisibility = .all }
            })
            .id(openCircuit.persistentModelID)
            #endif
        } else if let openFBD {
            #if os(iOS)
            FBDEditorView(diagram: openFBD, onBack: {
                withAnimation { selection = .loose; columnVisibility = .all }
            })
            .id(openFBD.persistentModelID)
            #endif
        } else if let openBeam {
            #if os(iOS)
            ShearBendingView(diagram: openBeam, onBack: {
                withAnimation { selection = .loose; columnVisibility = .all }
            })
            .id(openBeam.persistentModelID)
            #endif
        } else if let openVectorField {
            #if os(iOS)
            VectorFieldView(diagram: openVectorField, onBack: {
                withAnimation { selection = .loose; columnVisibility = .all }
            })
            .id(openVectorField.persistentModelID)
            #endif
        } else if let openTruss {
            #if os(iOS)
            TrussEditorView(diagram: openTruss, onBack: {
                withAnimation { selection = .loose; columnVisibility = .all }
            })
            .id(openTruss.persistentModelID)
            #endif
        } else if let openNotepad {
            NotepadEditorView(
                notepad: openNotepad,
                onHome: goHome,
                onToggleSidebar: toggleSidebar,
                onUndoManagerReady: { canvasUndoManager = $0 },
                requestedGraph: pendingGraphRequest,
                requestedGraphForce3D: pendingGraphForce3D
            )
            .id(openNotepad.persistentModelID)
        } else if selection == .library {
            LibraryView(
                onSelectBook: { book in
                    withAnimation { selection = .folder(book.persistentModelID) }
                },
                onRenameBook: beginFolderRename
            )
        } else if selectedFolder != nil {
            ContentUnavailableView {
                Label("Select a Note", systemImage: "doc.text")
            } description: {
                Text("Choose a note from a chapter, or create a new one.")
            }
        } else {
            NotepadGridView(
                notepads: sorted(notepads),
                books: recentBooks,
                showDates: showDates,
                onOpen: open,
                onOpenBook: { book in withAnimation { selection = .folder(book.persistentModelID) } },
                onNew: createNotepad,
                onRename: beginRename,
                onDelete: delete,
                onRenameBook: beginFolderRename,
                onDeleteBook: deleteFolder
            )
        }
    }

    /// Books ordered by most recent activity (latest note edit, or creation
    /// date for an empty book), for Home's "Recent Books" section.
    private var recentBooks: [Folder] {
        folders.sorted {
            let lhs = $0.notepads.map(\.lastEditedDate).max() ?? $0.createdDate
            let rhs = $1.notepads.map(\.lastEditedDate).max() ?? $1.createdDate
            return lhs > rhs
        }
    }

    // MARK: - Sidebar

    /// Only one sidebar is ever visible: the plain Home/Library list while
    /// browsing, or the notebook side panel while inside a book or note —
    /// never both at once.
    @ViewBuilder
    private var sidebar: some View {
        if let book = selectedFolder {
            ChapterSidebarView(
                book: book,
                looseNotes: [],
                graphHistory: openNotepad?.graphHistory ?? [],
                selectedNote: $openNotepad,
                onHome: goHome,
                canUndo: canvasUndoManager != nil,
                onUndo: { canvasUndoManager?.undo() },
                onRedo: { canvasUndoManager?.redo() },
                onAddNote: { addQuickNote(to: book) },
                onCreateNote: { chapter in createNote(in: chapter) },
                onNewChapter: { createChapter(for: book) },
                onRenameChapter: beginChapterRename,
                onDeleteChapter: deleteChapter,
                onOpenGraph: openGraph
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 280)
        } else if openNotepad != nil {
            ChapterSidebarView(
                book: nil,
                looseNotes: sorted(notepads.filter { $0.folder == nil }),
                graphHistory: openNotepad?.graphHistory ?? [],
                selectedNote: $openNotepad,
                onHome: goHome,
                canUndo: canvasUndoManager != nil,
                onUndo: { canvasUndoManager?.undo() },
                onRedo: { canvasUndoManager?.redo() },
                onAddNote: createNotepad,
                onCreateNote: { _ in },
                onNewChapter: {},
                onRenameChapter: { _ in },
                onDeleteChapter: { _ in },
                onOpenGraph: openGraph
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 280)
        } else {
            homeLibraryList
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        }
    }

    /// Shows/hides the entire sidebar column (Home/Library list or the
    /// notebook panel) via NavigationSplitView's own columnVisibility — the
    /// same mechanism the diagram editors already use — rather than trying
    /// to animate the column's width, which NavigationSplitView doesn't
    /// reliably re-layout for.
    private func toggleSidebar() {
        withAnimation {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    // Same light-green color for the "New note" pill and the sidebar
    // selection indicator — kept visually distinct from each other by
    // opacity alone, with selection more opaque so it doesn't get confused
    // with the permanently-highlighted "New note" button.
    private let sidebarAccent = PaperTheme.darkerColor(fromHex: "#f2f5da", by: 0.16)
    private let sidebarAccentOpacity = 0.6
    private let selectionOpacity = 0.85
    // Home gets its own distinct outline color, separate from every other
    // selectable row's shared sidebarAccent.
    private let homeSelectionColor = PaperTheme.color(fromHex: "#847D75")

    @ViewBuilder
    private func selectionBackground(_ isSelected: Bool, color: Color? = nil) -> some View {
        if isSelected {
            let tint = color ?? sidebarAccent
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(selectionOpacity))
                    .padding(.vertical, 2)
                Rectangle()
                    .fill(tint)
                    .frame(width: 3)
                    .padding(.vertical, 4)
                    .padding(.leading, 2)
            }
        }
    }

    private var homeLibraryList: some View {
        List(selection: $selection) {

            // ── Always-visible quick actions ──────────────────────────────
            Section {
                Button(action: createNotepad) {
                    Label("New note", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(sidebarAccent.opacity(sidebarAccentOpacity))
                        .padding(.vertical, 2)
                )
            }

            // ── Special – engineering tool creators ───────────────────────
            DisclosureGroup(isExpanded: $specialExpanded) {
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

                Button(action: createTruss) {
                    Label("New Truss", systemImage: "network")
                }
                .buttonStyle(.plain)
            } label: {
                Label("Special", systemImage: "sparkles")
                    .fontWeight(.semibold)
            }

            // ── Sort ──────────────────────────────────────────────────────
            Section("Sort by") {
                Picker("Sort by", selection: $sort) {
                    ForEach(NotepadSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            // ── Workspace – Home + Library ────────────────────────────────
            Section("Workspace") {
                Label("Home", systemImage: "house")
                    .tag(SidebarSelection.loose)
                    .dropDestination(for: NotepadDrag.self) { items, _ in
                        setFolder(nil, for: items)
                        return true
                    }
                    .listRowBackground(selectionBackground(selection == .loose, color: homeSelectionColor))

                Label("Library", systemImage: "books.vertical")
                    .tag(SidebarSelection.library)
                    .listRowBackground(selectionBackground(selection == .library))
            }

            // ── Other Projects – collapsible engineering diagrams ─────────
            DisclosureGroup(isExpanded: $otherProjectsExpanded) {

                DisclosureGroup(isExpanded: $circuitsExpanded) {
                    ForEach(circuits) { circ in
                        Label(circ.title, systemImage: "bolt.circle.fill")
                            .tag(SidebarSelection.circuit(circ.persistentModelID))
                            .listRowBackground(selectionBackground(selection == .circuit(circ.persistentModelID)))
                            .contextMenu {
                                Button { beginCircuitRename(circ) } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) { deleteCircuit(circ) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    if circuits.isEmpty {
                        Text("Tap Special → New Circuit to start.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } label: {
                    Label("Circuits", systemImage: "bolt.circle.fill")
                }

                DisclosureGroup(isExpanded: $fbdsExpanded) {
                    ForEach(fbds) { fbd in
                        Label(fbd.title, systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                            .tag(SidebarSelection.fbd(fbd.persistentModelID))
                            .listRowBackground(selectionBackground(selection == .fbd(fbd.persistentModelID)))
                            .contextMenu {
                                Button { beginFBDRename(fbd) } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) { deleteFBD(fbd) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    if fbds.isEmpty {
                        Text("Tap Special → New FBD to start.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } label: {
                    Label("FBD Diagrams", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                }

                DisclosureGroup(isExpanded: $beamsExpanded) {
                    ForEach(beams) { beam in
                        Label(beam.title, systemImage: "chart.xyaxis.line")
                            .tag(SidebarSelection.beam(beam.persistentModelID))
                            .listRowBackground(selectionBackground(selection == .beam(beam.persistentModelID)))
                            .contextMenu {
                                Button { beginBeamRename(beam) } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) { deleteBeam(beam) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    if beams.isEmpty {
                        Text("Tap Special → New Beam to start.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } label: {
                    Label("Beam Diagrams", systemImage: "chart.xyaxis.line")
                }

                DisclosureGroup(isExpanded: $vfsExpanded) {
                    ForEach(vectorFields) { vf in
                        Label(vf.title, systemImage: "arrow.clockwise.circle.fill")
                            .tag(SidebarSelection.vectorField(vf.persistentModelID))
                            .listRowBackground(selectionBackground(selection == .vectorField(vf.persistentModelID)))
                            .contextMenu {
                                Button { beginVFRename(vf) } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) { deleteVF(vf) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    if vectorFields.isEmpty {
                        Text("Tap Special → New Vector Field to start.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } label: {
                    Label("Vector Fields", systemImage: "arrow.clockwise.circle.fill")
                }

                DisclosureGroup(isExpanded: $trussesExpanded) {
                    ForEach(trusses) { truss in
                        Label(truss.title, systemImage: "network")
                            .tag(SidebarSelection.truss(truss.persistentModelID))
                            .listRowBackground(selectionBackground(selection == .truss(truss.persistentModelID)))
                            .contextMenu {
                                Button { beginTrussRename(truss) } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) { deleteTruss(truss) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    if trusses.isEmpty {
                        Text("Tap Special → New Truss to start.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } label: {
                    Label("Trusses", systemImage: "network")
                }

            } label: {
                Label("Other Projects", systemImage: "folder.badge.gearshape")
                    .fontWeight(.semibold)
            }
        }
        .navigationTitle("Notes")
        .safeAreaInset(edge: .bottom) { bottomBar }
        .onAppear {
            if !onboardingCompleted { showOnboarding = true }
            ChapterMigrationService.runIfNeeded(context: modelContext)
        }
        .onChange(of: onboardingCompleted) { _, completed in
            if !completed { showOnboarding = true }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                onboardingCompleted = true
                showOnboarding = false
            }
        }
        .sheet(isPresented: $showLayoutSettings) { SettingsView() }
        .sheet(isPresented: $showHandwritingMemory) {
            NavigationStack { HandwritingMemoryView() }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button { showLayoutSettings = true } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
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
        notepad.paperColorHex = (isDarkMode && oledBlack) ? "#000000" : defaultPaperColorHex
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
        // Opening a note that lives inside a book should bring up that
        // book's chapter sidebar, same as opening it via Library would.
        if let folder = notepad.folder {
            selection = .folder(folder.persistentModelID)
        }
        openNotepad = notepad
    }

    private func goHome() {
        withAnimation {
            selection = .loose
            openNotepad = nil
            canvasUndoManager = nil
            columnVisibility = .all
        }
    }

    private func openGraph(_ expression: String, force3D: Bool? = nil) {
        pendingGraphForce3D = force3D
        pendingGraphRequest = expression
        DispatchQueue.main.async { pendingGraphRequest = nil }
    }

    // MARK: - Chapter / notebook-panel note creation

    private func createNote(in chapter: Chapter) {
        let notepad = Notepad()
        notepad.paperStyleRaw = defaultPaperStyleRaw
        notepad.paperColorHex = (isDarkMode && oledBlack) ? "#000000" : defaultPaperColorHex
        notepad.assign(to: chapter)
        modelContext.insert(notepad)

        let firstPage = Page(pageIndex: 0)
        firstPage.notepad = notepad
        modelContext.insert(firstPage)

        openNotepad = notepad
    }

    /// Adds a note to the book's first chapter, creating one if it has none yet.
    private func addQuickNote(to book: Folder) {
        createNote(in: firstOrNewChapter(for: book))
    }

    private func firstOrNewChapter(for book: Folder) -> Chapter {
        if let existing = book.orderedChapters.first { return existing }
        let chapter = Chapter(name: "Chapter 1", orderIndex: 0)
        chapter.folder = book
        modelContext.insert(chapter)
        return chapter
    }

    private func createChapter(for book: Folder) {
        let chapter = Chapter(name: "Chapter \(book.chapters.count + 1)", orderIndex: book.chapters.count)
        chapter.folder = book
        modelContext.insert(chapter)
    }

    private func deleteChapter(_ chapter: Chapter) {
        if openNotepad?.chapter?.persistentModelID == chapter.persistentModelID {
            openNotepad = nil
        }
        modelContext.delete(chapter)
    }

    private func beginChapterRename(_ chapter: Chapter) {
        chapterRenameTarget = chapter
        chapterRenameText = chapter.name
        showChapterRenameAlert = true
    }

    private func commitChapterRename() {
        guard let target = chapterRenameTarget else { return }
        let trimmed = chapterRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        target.name = trimmed.isEmpty ? target.name : trimmed
        chapterRenameTarget = nil
    }

    private func delete(_ notepad: Notepad) {
        if openNotepad?.persistentModelID == notepad.persistentModelID { openNotepad = nil }
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
        target.title = trimmed.isEmpty ? "New note" : trimmed
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
        openCircuit = circuit
        // Give SwiftData a tick to assign the persistent ID before selecting.
        DispatchQueue.main.async {
            selection = .circuit(circuit.persistentModelID)
            withAnimation { columnVisibility = .detailOnly }
        }
    }

    private func deleteCircuit(_ circuit: CircuitDiagram) {
        if case let .circuit(id) = selection, id == circuit.persistentModelID {
            selection = .loose; openCircuit = nil
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
        openFBD = fbd
        DispatchQueue.main.async {
            selection = .fbd(fbd.persistentModelID)
            withAnimation { columnVisibility = .detailOnly }
        }
    }

    private func deleteFBD(_ fbd: FBDDiagram) {
        if case let .fbd(id) = selection, id == fbd.persistentModelID { selection = .loose; openFBD = nil }
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
        openBeam = beam
        DispatchQueue.main.async {
            selection = .beam(beam.persistentModelID)
            withAnimation { columnVisibility = .detailOnly }
        }
    }

    private func deleteBeam(_ beam: BeamDiagram) {
        if case let .beam(id) = selection, id == beam.persistentModelID { selection = .loose; openBeam = nil }
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
        openVectorField = vf
        DispatchQueue.main.async {
            selection = .vectorField(vf.persistentModelID)
            withAnimation { columnVisibility = .detailOnly }
        }
    }

    private func deleteVF(_ vf: VectorFieldDiagram) {
        if case let .vectorField(id) = selection, id == vf.persistentModelID { selection = .loose; openVectorField = nil }
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

    // MARK: - Truss CRUD

    private func createTruss() {
        let t = TrussDiagram(title: "Truss \(trusses.count + 1)")
        modelContext.insert(t)
        openTruss = t
        DispatchQueue.main.async {
            selection = .truss(t.persistentModelID)
            withAnimation { columnVisibility = .detailOnly }
        }
    }

    private func deleteTruss(_ t: TrussDiagram) {
        if case let .truss(id) = selection, id == t.persistentModelID { selection = .loose; openTruss = nil }
        modelContext.delete(t)
    }

    private func beginTrussRename(_ t: TrussDiagram) {
        trussRenameTarget = t
        trussRenameText   = t.title
        showTrussRenameAlert = true
    }

    private func commitTrussRename() {
        guard let target = trussRenameTarget else { return }
        let trimmed = trussRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        target.title = trimmed.isEmpty ? "New Truss" : trimmed
        trussRenameTarget = nil
    }
}

// MARK: - Grid View & Card Components

private struct NotepadGridView: View {
    let notepads: [Notepad]
    let books: [Folder]
    let showDates: Bool
    let onOpen: (Notepad) -> Void
    let onOpenBook: (Folder) -> Void
    let onNew: () -> Void
    let onRename: (Notepad) -> Void
    let onDelete: (Notepad) -> Void
    var onRenameBook: (Folder) -> Void = { _ in }
    var onDeleteBook: (Folder) -> Void = { _ in }

    private let noteColumns = [GridItem(.adaptive(minimum: 130, maximum: 165), spacing: 20)]
    private let bookColumns = [GridItem(.adaptive(minimum: 130, maximum: 165), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Home")
                    .font(.system(size: 30, weight: .bold, design: .serif))

                sectionHeader("Recent Notes")

                if notepads.isEmpty {
                    ContentUnavailableView {
                        Label("No Notes", systemImage: "doc")
                    } description: {
                        Text("Tap + to start a new note.")
                    }
                } else {
                    LazyVGrid(columns: noteColumns, spacing: 20) {
                        ForEach(notepads) { notepad in
                            Button { onOpen(notepad) } label: {
                                NotepadCard(notepad: notepad, showDate: showDates)
                            }
                            .buttonStyle(.plain)
                            .draggable(NotepadDrag(id: notepad.persistentModelID))
                            .contextMenu {
                                Button { onRename(notepad) } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) { onDelete(notepad) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                if !books.isEmpty {
                    Divider().opacity(0.4)

                    sectionHeader("Recent Books")

                    LazyVGrid(columns: bookColumns, spacing: 24) {
                        ForEach(books) { book in
                            Button { onOpenBook(book) } label: {
                                BookCard(book: book)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { onRenameBook(book) } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) { onDeleteBook(book) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Home")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onNew) { Label("New note", systemImage: "plus") }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Notepad.self, Page.self, Folder.self, CircuitDiagram.self,
                               FBDDiagram.self, BeamDiagram.self, VectorFieldDiagram.self],
                        inMemory: true)
}
