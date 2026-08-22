//
//  NotepadSettingsView.swift
//  Tolerance
//
//  The paper-style / settings menu opened from the top-right popover inside a
//  notepad. Controls background paper style, grid density, and paper theme.
//  All settings persist directly with the SwiftData Notepad model.
//

#if os(iOS)
import SwiftUI

struct NotepadSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var notepad: Notepad

    private var paperColorBinding: Binding<Color> {
        Binding(
            get: { PaperTheme.color(fromHex: notepad.paperColorHex) },
            set: {
                notepad.paperColorHex = PaperTheme.hex(from: $0)
                notepad.markEdited()
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Paper Style Selection
                Section("Paper Style") {
                    Picker("Style", selection: $notepad.paperStyleRaw) {
                        ForEach(PaperStyle.allCases) { style in
                            Label(style.displayName, systemImage: style.systemImage)
                                .tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .onChange(of: notepad.paperStyleRaw) { _, _ in
                        notepad.markEdited()
                    }
                }

                // MARK: - Grid / Line Spacing
                if notepad.paperStyle != .blank {
                    Section("Grid Density") {
                        VStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { Double(notepad.gridColumns) },
                                    set: {
                                        notepad.gridColumns = Int($0.rounded())
                                        notepad.markEdited()
                                    }
                                ),
                                in: 6...40,
                                step: 1
                            )
                            
                            Text("\(notepad.gridColumns) boxes per row")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // MARK: - Paper Color Presets & Custom
                Section("Paper Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                        ForEach(PaperTheme.presets, id: \.hex) { preset in
                            presetSwatch(preset)
                        }
                    }
                    .padding(.vertical, 6)

                    ColorPicker("Custom paper color", selection: paperColorBinding, supportsOpacity: false)
                }

                // MARK: - Information
                Section {
                    Label(
                        "The pen color is automatically inverted from the paper background to maintain high legibility.",
                        systemImage: "pencil.tip"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Paper & Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 460)
    }

    // MARK: - Swatch Helper

    private func presetSwatch(_ preset: PaperThemePreset) -> some View {
        let isSelected = notepad.paperColorHex.caseInsensitiveCompare(preset.hex) == .orderedSame
        let swatchColor = PaperTheme.color(fromHex: preset.hex)

        return Button {
            notepad.paperColorHex = preset.hex
            notepad.markEdited()
        } label: {
            RoundedRectangle(cornerRadius: 8)
                .fill(swatchColor)
                .frame(height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
