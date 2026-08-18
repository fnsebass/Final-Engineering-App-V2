//
//  NotepadEditorView.swift
//  Tolerance
//
//  Opens a single notepad for writing. Shows one page of the PencilKit canvas
//  at a time, with controls to move between pages and add new ones.
//

import SwiftUI
import SwiftData

struct NotepadEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var notepad: Notepad

    /// Which page (0-based) is currently on screen.
    @State private var currentPageIndex = 0

    private var pages: [Page] { notepad.orderedPages }

    private var currentPage: Page? {
        guard pages.indices.contains(currentPageIndex) else { return nil }
        return pages[currentPageIndex]
    }

    var body: some View {
        Group {
            if let page = currentPage {
                pageCanvas(for: page)
                    // A stable identity per page guarantees a fresh canvas
                    // (with that page's ink) whenever we navigate.
                    .id(page.persistentModelID)
            } else {
                ContentUnavailableView("No Pages", systemImage: "doc")
            }
        }
        .navigationTitle(notepad.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 16) {
                    Button {
                        goToPage(currentPageIndex - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(currentPageIndex <= 0)

                    Text("Page \(currentPageIndex + 1) of \(max(pages.count, 1))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button {
                        goToPage(currentPageIndex + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(currentPageIndex >= pages.count - 1)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: addPage) {
                    Label("Add Page", systemImage: "plus.rectangle.on.rectangle")
                }
            }
        }
        .onAppear {
            notepad.markEdited()
            currentPageIndex = min(currentPageIndex, max(pages.count - 1, 0))
        }
    }

    // MARK: - Page canvas (platform specific)

    @ViewBuilder
    private func pageCanvas(for page: Page) -> some View {
        #if os(iOS)
        PencilCanvasView(page: page)
            .ignoresSafeArea(.container, edges: .bottom)
        #else
        ContentUnavailableView {
            Label("Use an iPad", systemImage: "ipad.and.arrow.forward")
        } description: {
            Text("The drawing canvas and Apple Pencil features are available on iPad.")
        }
        #endif
    }

    // MARK: - Actions

    private func goToPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        currentPageIndex = index
    }

    private func addPage() {
        let newPage = Page(pageIndex: notepad.pages.count)
        newPage.notepad = notepad
        modelContext.insert(newPage)
        notepad.markEdited()
        // Jump to the freshly added page.
        currentPageIndex = notepad.orderedPages.count - 1
    }
}
