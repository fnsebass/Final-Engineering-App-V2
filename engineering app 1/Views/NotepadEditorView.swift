//
//  NotepadEditorView.swift
//  Tolerance
//
//  Opens a single notepad. In Phase 2 this is a simple placeholder; the
//  PencilKit canvas and page navigation arrive in Phase 3.
//

import SwiftUI

struct NotepadEditorView: View {
    @Bindable var notepad: Notepad

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            Text(notepad.title)
                .font(.title2.bold())
            Text("\(notepad.orderedPages.count) page(s)")
                .foregroundStyle(.secondary)
            Text("Canvas editor coming in Phase 3.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .navigationTitle(notepad.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { notepad.markEdited() }
    }
}
