//
//  HomeView.swift
//  Tolerance
//
//  Home screen: a grid of all notepads. Users can create, rename, and delete
//  notepads here, and tap one to open it in the canvas editor.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    // Newest-edited notepads appear first.
    @Query(sort: \Notepad.lastEditedDate, order: .reverse) private var notepads: [Notepad]

    // Rename sheet state.
    @State private var renameTarget: Notepad?
    @State private var renameText: String = ""

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 20)]

    var body: some View {
        NavigationStack {
            Group {
                if notepads.isEmpty {
                    ContentUnavailableView {
                        Label("No Notepads Yet", systemImage: "square.and.pencil")
                    } description: {
                        Text("Tap the + button to create your first notepad.")
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(notepads) { notepad in
                                NavigationLink(value: notepad) {
                                    NotepadCard(notepad: notepad)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        beginRename(notepad)
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        delete(notepad)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Tolerance")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: createNotepad) {
                        Label("New Notepad", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: Notepad.self) { notepad in
                NotepadEditorView(notepad: notepad)
            }
        }
        .alert("Rename Notepad", isPresented: renameBinding) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") { commitRename() }
        }
    }

    // MARK: - Actions

    private func createNotepad() {
        let notepad = Notepad()
        modelContext.insert(notepad)
        // Every new notepad starts with a single blank page.
        let firstPage = Page(pageIndex: 0)
        firstPage.notepad = notepad
        modelContext.insert(firstPage)
    }

    private func delete(_ notepad: Notepad) {
        modelContext.delete(notepad)
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

    /// Drives the rename alert's presentation from `renameTarget`.
    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }
}

/// A single notepad "card" shown in the home grid.
private struct NotepadCard: View {
    let notepad: Notepad

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .frame(height: 160)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                )
                .overlay(alignment: .bottomTrailing) {
                    Text("\(notepad.pages.count) pg")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                        .padding(8)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(notepad.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(notepad.lastEditedDate, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Notepad.self, Page.self], inMemory: true)
}
