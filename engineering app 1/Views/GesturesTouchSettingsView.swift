//
//  GesturesTouchSettingsView.swift
//  Tolerance
//
//  Multi-touch gesture shortcuts, finger-vs-stylus action mapping, and
//  touch lockout. "Finger Touch Does" and "Ignore Touch Input While Pencil
//  Is Active" are wired directly to PKCanvasView.drawingPolicy in
//  PencilCanvasView (.pencilOnly / .anyInput / .default).
//

import SwiftUI

enum FingerAction: String, CaseIterable, Identifiable {
    case pan, draw
    var id: String { rawValue }
    var displayName: String { self == .pan ? "Pan the Canvas" : "Draw" }
}

struct GesturesTouchSettingsView: View {
    @AppStorage("settings.gestures.twoFingerUndo") private var twoFingerUndo = false
    @AppStorage("settings.gestures.threeFingerRedo") private var threeFingerRedo = false
    @AppStorage("settings.gestures.fingerAction") private var fingerActionRaw = FingerAction.pan.rawValue
    @AppStorage("settings.gestures.touchLockout") private var touchLockout = true

    var body: some View {
        Form {
            Section {
                Toggle("Two-Finger Undo", isOn: $twoFingerUndo)
                Toggle("Three-Finger Redo", isOn: $threeFingerRedo)
            } header: {
                Text("Multi-Touch Shortcuts")
            } footer: {
                Text("Tap the canvas with two fingers to undo, or three fingers to redo, when enabled.")
                    .font(.caption)
            }

            Section {
                Picker("Finger Touch Does", selection: $fingerActionRaw) {
                    ForEach(FingerAction.allCases) { action in
                        Text(action.displayName).tag(action.rawValue)
                    }
                }
            } footer: {
                Text("Pan keeps the canvas Apple Pencil-only, with fingers only scrolling. Draw lets a finger write directly on the canvas too.")
                    .font(.caption)
            }

            Section {
                Toggle("Ignore Touch Input While Pencil Is Active", isOn: $touchLockout)
                    .disabled(fingerActionRaw != FingerAction.draw.rawValue)
            } footer: {
                Text(fingerActionRaw == FingerAction.draw.rawValue
                     ? "Once you touch the canvas with Apple Pencil, finger touches stop drawing for the rest of that session — prevents accidental smudges while writing."
                     : "Only applies when Finger Touch Does is set to Draw.")
                    .font(.caption)
            }
        }
        .navigationTitle("Gestures & Touch")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack { GesturesTouchSettingsView() }
}
