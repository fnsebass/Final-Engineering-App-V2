//
//  LibraryView.swift
//  Tolerance
//
//  The "Library" destination: a grid of Books (Folders), shaped like actual
//  book covers — solid color, title printed on the cover, user-choosable
//  icon. Tapping one asks HomeView to select it (HomeView then swaps its
//  sidebar to the notebook side panel for that book). A dashed "New Book"
//  card always trails the real ones, mirroring the "+" note card used
//  elsewhere — tapping it creates a book.
//

import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var folders: [Folder]
    var onSelectBook: (Folder) -> Void = { _ in }
    var onRenameBook: (Folder) -> Void = { _ in }

    @State private var showNewBookAlert = false
    @State private var newBookName = ""
    @State private var customizeTarget: Folder?

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 170), spacing: 24)]

    private var sortedBooks: [Folder] {
        folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(sortedBooks) { book in
                    Button { onSelectBook(book) } label: {
                        BookCard(book: book)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { onRenameBook(book) } label: {
                            Label("Rename Book", systemImage: "pencil")
                        }
                        Button { customizeTarget = book } label: {
                            Label("Customize Book", systemImage: "paintpalette")
                        }
                        Button(role: .destructive) { modelContext.delete(book) } label: {
                            Label("Delete Book", systemImage: "trash")
                        }
                    }
                }

                Button {
                    newBookName = ""
                    showNewBookAlert = true
                } label: {
                    NewBookCard()
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .navigationTitle("Library")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("New Book", isPresented: $showNewBookAlert) {
            TextField("Book name", text: $newBookName)
            Button("Cancel", role: .cancel) { newBookName = "" }
            Button("Create") { createBook() }
        }
        .sheet(item: $customizeTarget) { book in
            BookCustomizeView(book: book)
        }
    }

    private func createBook() {
        let trimmed = newBookName.trimmingCharacters(in: .whitespacesAndNewlines)
        let book = Folder(name: trimmed.isEmpty ? "New Book" : trimmed)
        book.coverColorHex = BookTheme.nextColorHex(existingCount: folders.count)
        modelContext.insert(book)
        newBookName = ""
    }
}

// MARK: - Book-shaped cards

/// Portrait, roughly 2:3 — matches the reference photo's measured proportions.
let bookAspectRatio: CGFloat = 2.0 / 3.0

struct BookCard: View {
    @Bindable var book: Folder

    private var coverColor: Color { PaperTheme.color(fromHex: book.coverColorHex) }
    /// The left "spine" sliver — a visibly darker shade of the cover color.
    private var spineColor: Color { PaperTheme.darkerColor(fromHex: book.coverColorHex, by: 0.18) }
    /// The faint divider line — auto-contrasts to whichever of dark/light
    /// grey suits the cover's own brightness.
    private var lineColor: Color { PaperTheme.inkColor(forPaperHex: book.coverColorHex) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let leftSliver = w / 16
            let rightSliver = leftSliver / 2
            let lineY = h / 3   // 2/3 up from the bottom == 1/3 down from the top
            let lineMargin = w * 0.14   // extra inset beyond the slivers, on top of it

            ZStack(alignment: .topLeading) {
                coverColor

                // Left spine sliver — darker shade of the cover color.
                HStack(spacing: 0) {
                    Rectangle().fill(spineColor).frame(width: leftSliver)
                    Spacer(minLength: 0)
                }

                // Right page-edge sliver — white, narrower than the spine.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle().fill(Color.white).frame(width: rightSliver)
                }

                // Faint divider — shorter than the cover's plain middle area,
                // well clear of both slivers on either side.
                Path { p in
                    p.move(to: CGPoint(x: leftSliver + lineMargin, y: lineY))
                    p.addLine(to: CGPoint(x: w - rightSliver - lineMargin, y: lineY))
                }
                .stroke(lineColor.opacity(0.35), lineWidth: 1)

                // Title — sits just above the divider, not pinned to the top.
                Text(book.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.bottom, 8)
                    .padding(.leading, leftSliver + lineMargin)
                    .padding(.trailing, rightSliver + lineMargin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: lineY, alignment: .bottom)

                Text("\(book.chapters.count) chapters")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 11)
                    .padding(.leading, leftSliver + 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 11)
                    .padding(.trailing, rightSliver + 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(bookAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(spineColor, lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
    }
}

private struct NewBookCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            .foregroundStyle(.tertiary)
            .aspectRatio(bookAspectRatio, contentMode: .fit)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                    Text("New Book")
                        .font(.footnote.weight(.medium))
                }
                .foregroundStyle(.secondary)
            )
    }
}

// MARK: - Customize sheet (cover color + icon)

private struct BookCustomizeView: View {
    @Bindable var book: Folder
    @Environment(\.dismiss) private var dismiss

    private let colorColumns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
    private let iconColumns = [GridItem(.adaptive(minimum: 44), spacing: 12)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        BookCard(book: book)
                            .frame(width: 140)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section("Cover Color") {
                    LazyVGrid(columns: colorColumns, spacing: 12) {
                        ForEach(BookTheme.coverPalette) { option in
                            colorSwatch(option)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Icon") {
                    LazyVGrid(columns: iconColumns, spacing: 12) {
                        ForEach(BookTheme.icons, id: \.self) { icon in
                            iconSwatch(icon)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Customize Book")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 460)
    }

    private func colorSwatch(_ option: BookColorOption) -> some View {
        let isSelected = book.coverColorHex.caseInsensitiveCompare(option.hex) == .orderedSame
        return Button {
            book.coverColorHex = option.hex
        } label: {
            RoundedRectangle(cornerRadius: 8)
                .fill(PaperTheme.color(fromHex: option.hex))
                .frame(height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(isSelected ? 0.8 : 0.1), lineWidth: isSelected ? 3 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func iconSwatch(_ icon: String) -> some View {
        let isSelected = book.iconName == icon
        return Button {
            book.iconName = icon
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(width: 44, height: 44)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack { LibraryView() }
        .modelContainer(for: [Notepad.self, Page.self, Folder.self, Chapter.self], inMemory: true)
}
