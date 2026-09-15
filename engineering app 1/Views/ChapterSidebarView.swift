//
//  ChapterSidebarView.swift
//  Tolerance
//
//  The notebook side panel. Replaces HomeView's plain Home/Library list
//  whenever you're inside a book or have a note open, so there's only ever
//  one sidebar showing at a time. Top bar: Home / Undo / Redo / Add. Below
//  that: a book title header (or "Notes" when there's no book — a loose
//  note opened straight from Home) with CHAPTERS-or-NOTES / HISTORY / GRAPHS
//  tabs. All creation/rename logic is owned by HomeView and reached here via
//  closures, so this view stays purely presentational.
//

import SwiftUI
import SwiftData

private enum PanelTab: Hashable {
    case primary, history, graphs

    func label(hasBook: Bool) -> String {
        switch self {
        case .primary: return hasBook ? "CHAPTERS" : "NOTES"
        case .history: return "HISTORY"
        case .graphs:  return "GRAPHS"
        }
    }
}

struct ChapterSidebarView: View {
    /// nil when showing a loose note opened straight from Home (no book context).
    let book: Folder?
    /// Used only when `book == nil` — every unfiled note, for the flat NOTES/HISTORY lists.
    let looseNotes: [Notepad]
    /// Graph history for whichever note is currently open, if any.
    let graphHistory: [String]

    @Binding var selectedNote: Notepad?

    var onHome: () -> Void
    var canUndo: Bool
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onAddNote: () -> Void
    var onCreateNote: (Chapter) -> Void
    var onNewChapter: () -> Void
    var onRenameChapter: (Chapter) -> Void
    var onDeleteChapter: (Chapter) -> Void
    /// Second param: nil = auto-detect 2-D/3-D, true = force 3-D, false = force 2-D.
    var onOpenGraph: (String, Bool?) -> Void

    @State private var tab: PanelTab = .primary

    private var totalNotes: Int { book?.notepads.count ?? looseNotes.count }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            header
            Divider()
            tabRow
            Divider()

            switch tab {
            case .primary: primaryTab
            case .history: historyList
            case .graphs:  graphsList
            }

            Divider()
            footer
        }
        .background(.regularMaterial)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button(action: onHome) {
                Image(systemName: "house")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)

            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!canUndo)

            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!canUndo)

            Spacer()

            Button(action: onAddNote) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack {
            Text(book?.name ?? "Notes")
                .font(.headline)
                .lineLimit(1)
            Spacer()
        }
        .padding(12)
    }

    private var tabRow: some View {
        HStack(spacing: 0) {
            ForEach([PanelTab.primary, .history, .graphs], id: \.self) { candidate in
                Button { tab = candidate } label: {
                    Text(candidate.label(hasBook: book != nil))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tab == candidate ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if tab == candidate {
                                Rectangle().fill(Color.accentColor).frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Primary tab (chapters, or a flat notes grid when there's no book)

    @ViewBuilder
    private var primaryTab: some View {
        if let book {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(book.orderedChapters) { chapter in
                        ChapterSectionRow(
                            chapter: chapter,
                            selectedNote: $selectedNote,
                            onCreateNote: { onCreateNote(chapter) },
                            onRename: { onRenameChapter(chapter) },
                            onDelete: { onDeleteChapter(chapter) }
                        )
                    }

                    Button(action: onNewChapter) {
                        Label("New Chapter", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
                .padding(.vertical, 4)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 10)], spacing: 10) {
                    ForEach(looseNotes) { note in
                        Button { selectedNote = note } label: {
                            NotepadCard(notepad: note, showDate: false)
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: onAddNote) {
                        NewNoteCard()
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
            }
        }
    }

    // MARK: - History tab

    private var historyList: some View {
        let notes = (book?.notepads ?? looseNotes).sorted { $0.lastEditedDate > $1.lastEditedDate }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(notes) { note in
                    Button { selectedNote = note } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title).font(.subheadline).lineLimit(1)
                            Text(note.lastEditedDate, format: .relative(presentation: .named))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Graphs tab

    /// Replaces the canvas's old left-edge "Quick Graph" drawer — the
    /// type-in field lives here now, alongside the history it feeds.
    private var graphsList: some View {
        VStack(spacing: 0) {
            quickGraphField
            Divider()
            graphHistoryList
        }
    }

    @State private var quickGraphExpr = ""

    private var quickGraphField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Quick Graph", systemImage: "function")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(quickGraphExpr.isEmpty ? "e.g. x^2 + sin(x)" : quickGraphExpr)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(quickGraphExpr.isEmpty ? .tertiary : .primary)
                }
                Spacer(minLength: 0)
                if !quickGraphExpr.isEmpty {
                    Button {
                        quickGraphExpr.removeLast()
                    } label: {
                        Image(systemName: "delete.backward")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .opacity(selectedNote == nil ? 0.5 : 1)

            FunctionKeyboardStrip { key in quickGraphExpr += key }
                .disabled(selectedNote == nil)

            EquationKeypad { key in quickGraphExpr += key }
                .disabled(selectedNote == nil)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 6) {
                Button("Plot") { plotQuickGraph() }
                    .frame(maxWidth: .infinity)

                Button {
                    plotQuickGraph(force3D: true)
                } label: {
                    Label("3-D", systemImage: "cube")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .disabled(selectedNote == nil || quickGraphExpr.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
    }

    private func plotQuickGraph(force3D: Bool? = nil) {
        let expr = quickGraphExpr.trimmingCharacters(in: .whitespaces)
        guard !expr.isEmpty else { return }
        onOpenGraph(expr, force3D)
        quickGraphExpr = ""
    }

    @ViewBuilder
    private var graphHistoryList: some View {
        if graphHistory.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
                Text(selectedNote == nil ? "Open a note to see its graphs." : "No graphs plotted yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(graphHistory.reversed(), id: \.self) { expr in
                        Button { onOpenGraph(expr, nil) } label: {
                            HStack {
                                Image(systemName: "function")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(expr)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Text("\(totalNotes) notes")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}

// MARK: - Per-chapter section row

private struct ChapterSectionRow: View {
    @Bindable var chapter: Chapter
    @Binding var selectedNote: Notepad?
    var onCreateNote: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    @State private var isExpanded = true

    private let cardColumns = [GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 10)]

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            LazyVGrid(columns: cardColumns, spacing: 10) {
                ForEach(chapter.orderedNotes) { note in
                    Button { selectedNote = note } label: {
                        NotepadCard(notepad: note, showDate: false)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onCreateNote) {
                    NewNoteCard()
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        } label: {
            HStack {
                Text(chapter.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: onCreateNote) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                Menu {
                    Button { onRename() } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) { onDelete() } label: { Label("Delete Chapter", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
