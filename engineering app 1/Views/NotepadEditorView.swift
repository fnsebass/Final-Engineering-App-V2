//
//  NotepadEditorView.swift
//  Tolerance
//
//  Hosts one notepad's infinite canvas, with a settings gear at the top-left
//  for grid/paper options.
//

import SwiftUI
import SwiftData

struct NotepadEditorView: View {
    @Bindable var notepad: Notepad
    @State private var showSettings = false

    var body: some View {
        content
            .navigationTitle(notepad.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .popover(isPresented: $showSettings) {
                        NotepadSettingsView(notepad: notepad)
                    }
                }
            }
            #endif
            .onAppear { notepad.markEdited() }
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        CanvasWorkspace(notepad: notepad)
        #else
        ContentUnavailableView {
            Label("Use an iPad", systemImage: "ipad.and.arrow.forward")
        } description: {
            Text("The drawing canvas and Apple Pencil features are available on iPad.")
        }
        #endif
    }
}
