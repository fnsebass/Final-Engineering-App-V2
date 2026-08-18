//
//  NotepadSettingsView.swift
//  Tolerance
//
//  The settings menu (opened from the gear at the top-left inside a notepad).
//  Controls the grid scale, whether the grid shows, and the paper color. The
//  pen color always follows automatically as the opposite of the paper.
//

#if os(iOS)
import SwiftUI

struct NotepadSettingsView: View {
    @Bindable var notepad: Notepad

    private var paperColorBinding: Binding<Color> {
        Binding(
            get: { PaperTheme.color(fromHex: notepad.paperColorHex) },
            set: { notepad.paperColorHex = PaperTheme.hex(from: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Paper color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                        ForEach(PaperTheme.presets, id: \.hex) { preset in
                            presetSwatch(preset.hex)
                        }
                    }
                    .padding(.vertical, 4)
                    ColorPicker("Custom paper color", selection: paperColorBinding, supportsOpacity: false)
                }

                Section("Grid") {
                    Toggle("Show grid", isOn: $notepad.showsGrid)
                    HStack {
                        Text("Grid size")
                        Slider(value: $notepad.gridSpacing, in: 12...72, step: 2)
                        Text("\(Int(notepad.gridSpacing))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .disabled(!notepad.showsGrid)
                }

                Section {
                    Label("The pen color is always set to the opposite of the paper, so your ink stays legible.",
                          systemImage: "pencil.tip")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Notepad Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .frame(minWidth: 340, minHeight: 420)
    }

    private func presetSwatch(_ hex: String) -> some View {
        let isSelected = notepad.paperColorHex.caseInsensitiveCompare(hex) == .orderedSame
        return Button {
            notepad.paperColorHex = hex
        } label: {
            RoundedRectangle(cornerRadius: 8)
                .fill(PaperTheme.color(fromHex: hex))
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0))
        }
        .buttonStyle(.plain)
    }
}
#endif
