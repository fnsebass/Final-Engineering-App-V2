//
//  NotepadSettingsView.swift
//  Tolerance
//
//  The paper-style / settings menu opened from the gear (top-right) inside a
//  notepad. Controls the background paper style, its spacing, and the paper
//  color. The pen color always follows automatically as the opposite of the
//  paper. All settings persist with the notepad.
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
                Section("Paper style") {
                    Picker("Style", selection: $notepad.paperStyleRaw) {
                        ForEach(PaperStyle.allCases) { style in
                            Label(style.displayName, systemImage: style.systemImage).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if notepad.paperStyle != .blank {
                    Section("Grid size") {
                        Slider(
                            value: Binding(
                                get: { Double(notepad.gridColumns) },
                                set: { notepad.gridColumns = Int($0.rounded()) }
                            ),
                            in: 6...40, step: 1
                        )
                        Text("\(notepad.gridColumns) boxes per row")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Paper color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                        ForEach(PaperTheme.presets, id: \.hex) { preset in
                            presetSwatch(preset.hex)
                        }
                    }
                    .padding(.vertical, 4)
                    ColorPicker("Custom paper color", selection: paperColorBinding, supportsOpacity: false)
                }

                Section {
                    Label("The pen color is always the opposite of the paper, so ink stays legible.",
                          systemImage: "pencil.tip")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Paper & Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .frame(minWidth: 360, minHeight: 460)
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
