//
//  PencilCanvasView.swift
//  Tolerance
//
//  A SwiftUI wrapper around PencilKit's PKCanvasView. Handles loading a page's
//  saved ink, showing the system tool picker (pen / eraser / colors / width),
//  and saving changes back to the SwiftData `Page` as the user draws.
//
//  PencilKit's canvas is only available on iOS/iPadOS, so on other platforms
//  we compile a lightweight placeholder instead (see NotepadEditorView).
//

#if os(iOS)
import SwiftUI
import PencilKit

struct PencilCanvasView: UIViewRepresentable {
    /// The page whose ink this canvas edits. Drawing changes are written back
    /// into `page.drawingData`.
    let page: Page

    /// Optional hook fired whenever the drawing changes. Phase 4 uses this to
    /// inspect newly drawn strokes for a circle gesture.
    var onDrawingChanged: ((PKDrawing, PKCanvasView) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        // Allow both Apple Pencil and finger so the app is usable everywhere;
        // the Pencil is still the intended tool for engineering notes.
        canvas.drawingPolicy = .anyInput
        canvas.alwaysBounceVertical = true
        canvas.backgroundColor = .systemBackground

        // Load any previously saved ink for this page.
        if let drawing = try? PKDrawing(data: page.drawingData) {
            canvas.drawing = drawing
        }
        context.coordinator.canvas = canvas

        // Show the floating tool picker and make the canvas able to receive it.
        let toolPicker = PKToolPicker()
        toolPicker.addObserver(canvas)
        toolPicker.setVisible(true, forFirstResponder: canvas)
        context.coordinator.toolPicker = toolPicker
        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
        }

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasView
        weak var canvas: PKCanvasView?
        var toolPicker: PKToolPicker?

        // Skip the very first "did change" that fires when we load the drawing,
        // so we don't immediately re-save unchanged data.
        private var hasLoaded = false

        init(_ parent: PencilCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard hasLoaded else {
                hasLoaded = true
                return
            }
            let drawing = canvasView.drawing
            parent.page.drawingData = drawing.dataRepresentation()
            parent.page.notepad?.markEdited()
            parent.onDrawingChanged?(drawing, canvasView)
        }
    }
}
#endif
