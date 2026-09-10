//
//  PenButtonsSettingsView.swift
//  Tolerance
//
//  Mapping for physical stylus button events (Apple Pencil Pro squeeze,
//  Apple Pencil 2 double-tap), read directly by PencilCanvasView's
//  UIPencilInteractionDelegate. Squeeze holds the mapped tool/action while
//  pressed for Toggle Eraser only; every other action (including double-tap)
//  fires once.
//

import SwiftUI

enum PenButtonAction: String, CaseIterable, Identifiable {
    case showToolPalette, toggleEraser, triggerLasso, switchColors, undo, redo, none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .showToolPalette: return "Show Tool Palette"
        case .toggleEraser:    return "Toggle Eraser"
        case .triggerLasso:    return "Trigger Lasso Tool"
        case .switchColors:    return "Switch Colors"
        case .undo:            return "Undo"
        case .redo:            return "Redo"
        case .none:            return "No Action"
        }
    }
}

struct PenButtonsSettingsView: View {
    @AppStorage("settings.penButtons.singleClick") private var singleClickRaw = PenButtonAction.showToolPalette.rawValue
    @AppStorage("settings.penButtons.doubleClick") private var doubleClickRaw = PenButtonAction.toggleEraser.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Squeeze / Single Click", selection: $singleClickRaw) {
                    ForEach(PenButtonAction.allCases) { action in
                        Text(action.displayName).tag(action.rawValue)
                    }
                }
                Picker("Double-Tap / Double Click", selection: $doubleClickRaw) {
                    ForEach(PenButtonAction.allCases) { action in
                        Text(action.displayName).tag(action.rawValue)
                    }
                }
            } header: {
                Text("Button Mapping")
            } footer: {
                Text("Show Tool Palette opens the curved eraser/highlighter/line/shape/color palette right where you're squeezing. Toggle Eraser holds while squeezed and toggles on double-tap. Every other action fires once per squeeze or double-tap.")
                    .font(.caption)
            }
        }
        .navigationTitle("Pen Buttons")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack { PenButtonsSettingsView() }
}
