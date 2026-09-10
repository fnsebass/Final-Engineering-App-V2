//
//  PaperLayoutSettingsView.swift
//  Tolerance
//
//  Grid style and background color are defaults applied to newly created
//  notepads (per-notepad overrides live in NotepadSettingsView). Page Size
//  and Margins are global, live canvas guides — GridContentView in
//  PencilCanvasView.swift reads them straight from UserDefaults on every
//  redraw, so they apply to every notepad immediately.
//

import SwiftUI

enum PageDimension: String, CaseIterable, Identifiable {
    case a4, letter, infinite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .a4:       return "A4"
        case .letter:   return "Letter"
        case .infinite: return "Infinite Canvas"
        }
    }
}

struct PaperLayoutSettingsView: View {
    @AppStorage(LayoutPrefs.defaultPaperStyle) private var defaultPaperStyleRaw = PaperStyle.grid.rawValue
    @AppStorage(LayoutPrefs.defaultPaperColorHex) private var defaultPaperColorHex = "#FFFFFF"
    @AppStorage("settings.paper.pageDimension") private var pageDimensionRaw = PageDimension.infinite.rawValue
    @AppStorage("settings.paper.margin") private var margin = 24.0

    private var paperColorBinding: Binding<Color> {
        Binding(
            get: { PaperTheme.color(fromHex: defaultPaperColorHex) },
            set: { defaultPaperColorHex = PaperTheme.hex(from: $0) }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Grid Style", selection: $defaultPaperStyleRaw) {
                    ForEach(PaperStyle.allCases) { style in
                        Label(style.displayName, systemImage: style.systemImage)
                            .tag(style.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Default Grid")
            } footer: {
                Text("Used for every new notepad you create. Isometric and millimeter graph styles are planned but not yet available.")
                    .font(.caption)
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                    ForEach(PaperTheme.presets) { preset in
                        presetSwatch(preset)
                    }
                }
                .padding(.vertical, 6)

                ColorPicker("Custom background color", selection: paperColorBinding, supportsOpacity: false)
            } header: {
                Text("Default Background Color")
            }

            Section {
                Picker("Page Size", selection: $pageDimensionRaw) {
                    ForEach(PageDimension.allCases) { dimension in
                        Text(dimension.displayName).tag(dimension.rawValue)
                    }
                }
            } footer: {
                Text("The canvas still scrolls continuously — A4/Letter show as dashed horizontal page-break guides rather than a hard paginated layout.")
                    .font(.caption)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Slider(value: $margin, in: 0...72, step: 2)
                    Text("\(Int(margin)) pt margin")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Margins")
            } footer: {
                Text("Shown as dashed vertical guide lines on every notepad's canvas.")
                    .font(.caption)
            }
        }
        .navigationTitle("Paper & Layout")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func presetSwatch(_ preset: PaperThemePreset) -> some View {
        let isSelected = defaultPaperColorHex.caseInsensitiveCompare(preset.hex) == .orderedSame
        let swatchColor = PaperTheme.color(fromHex: preset.hex)

        return Button {
            defaultPaperColorHex = preset.hex
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

#Preview {
    NavigationStack { PaperLayoutSettingsView() }
}
