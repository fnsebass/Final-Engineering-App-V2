//
//  NotepadEditorView.swift
//  Tolerance
//
//  Custom two-row header:
//    Row 1 — mode tabs: Math (grid paper) | English (lined) | Draw (blank)
//    Row 2 — back · title · pencil tips · tools · ruler · settings
//
//  Pencil tips: tap to select, long-press to open a color picker for that slot.
//  Colors per slot persist for the session and update live if the slot is active.
//  Drawing state (activeTool, penColor, rulerActive) lives here so the toolbar
//  and the canvas share it through bindings.
//

import SwiftUI
import SwiftData

// MARK: - Color ↔ hex helpers (iOS only, private to this file)
#if os(iOS)
private extension Color {
    init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        self.init(.sRGB,
                  red:   Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >>  8) & 0xFF) / 255,
                  blue:  Double( v        & 0xFF) / 255)
    }
    func hexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
}
#endif

struct NotepadEditorView: View {
    @Bindable var notepad: Notepad
    var onBack: () -> Void = {}

    @State private var showSettings = false
    @State private var isEditingTitle = false
    @State private var tempTitle = ""

    // Drawing state — owned here, passed as bindings to CanvasWorkspace.
    #if os(iOS)
    @State private var activeTool: DrawingTool = .pen
    @State private var penColor: Color = Color(red: 0.15, green: 0.15, blue: 0.15)
    @State private var rulerActive: Bool = false

    // Pencil slot selection — persisted globally so it's the same across all notepads.
    @AppStorage("selectedPencilSlot") private var selectedColorTag: Int = 0

    // Per-slot pencil colors — persisted as hex strings so choices survive app launches.
    @AppStorage("pencilSlot0") private var pencilHex0: String = "#262626"  // Graphite
    @AppStorage("pencilSlot1") private var pencilHex1: String = "#173B9E"  // Blueprint
    @AppStorage("pencilSlot2") private var pencilHex2: String = "#D48008"  // Amber
    @AppStorage("pencilSlot3") private var pencilHex3: String = "#127038"  // PCB Green
    @AppStorage("pencilSlot4") private var pencilHex4: String = "#BD1414"  // Warning Red

    // Long-press color-picker state
    @State private var longPressedPencilIndex: Int? = nil
    @State private var pickerColor: Color = .black
    #endif

    var body: some View {
        content
            .onAppear {
                Task { @MainActor in notepad.markEdited() }
                #if os(iOS)
                syncPenColorToBackground()
                #endif
            }
            #if os(iOS)
            .onChange(of: notepad.paperColorHex) { _, _ in syncPenColorToBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { headerBar }
            #endif
    }

    #if os(iOS)
    // Returns the Color for a given slot index, reading from persisted hex.
    private func pencilColor(at i: Int) -> Color {
        let hexes = [pencilHex0, pencilHex1, pencilHex2, pencilHex3, pencilHex4]
        guard i >= 0 && i < hexes.count else { return .black }
        return Color(hex: hexes[i]) ?? .black
    }

    // Persists a new color hex for the given slot index.
    private func setPencilHex(_ hex: String, at i: Int) {
        switch i {
        case 0: pencilHex0 = hex
        case 1: pencilHex1 = hex
        case 2: pencilHex2 = hex
        case 3: pencilHex3 = hex
        case 4: pencilHex4 = hex
        default: break
        }
    }

    // Auto-selects white on dark paper, the current slot color on light paper.
    private func syncPenColorToBackground() {
        let hex = notepad.paperColorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let isDark: Bool
        if hex.count == 6, let v = UInt64(hex, radix: 16) {
            let r = Double((v >> 16) & 0xFF) / 255
            let g = Double((v >>  8) & 0xFF) / 255
            let b = Double( v        & 0xFF) / 255
            isDark = 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.5
        } else {
            isDark = false
        }
        penColor = isDark ? .white : pencilColor(at: selectedColorTag)
    }
    #endif

    // MARK: - Canvas content

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        CanvasWorkspace(
            notepad: notepad,
            activeTool: $activeTool,
            penColor: $penColor,
            rulerActive: $rulerActive
        )
        #else
        ContentUnavailableView {
            Label("Use an iPad", systemImage: "ipad.and.arrow.forward")
        } description: {
            Text("The drawing canvas and Apple Pencil features are optimized for iPadOS.")
        }
        #endif
    }

    // MARK: - Header bar (iOS only)

    #if os(iOS)
    private var headerBar: some View {
        VStack(spacing: 0) {
            modeTabRow
            Divider()
            toolRow
            Divider()
        }
        .background(.bar)
    }

    // MARK: Mode tabs

    private var modeTabRow: some View {
        HStack(spacing: 0) {
            modeTab("Math",    icon: "function",       style: .grid)
            modeTab("English", icon: "text.alignleft", style: .lined)
            modeTab("Draw",    icon: "pencil.tip",     style: .blank)
        }
        .frame(height: 32)
    }

    private func modeTab(_ label: String, icon: String, style: PaperStyle) -> some View {
        let active = notepad.paperStyle == style
        return Button { notepad.paperStyle = style } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .background(active ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: Tool row  (back · title · pencil tips · tools · ruler · settings)

    private var toolRow: some View {
        HStack(spacing: 0) {
            // ── Back ─────────────────────────────────────────
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // ── Title ─────────────────────────────────────────
            titleControl

            Spacer(minLength: 6)

            // ── Pencil tips (tap = select, long-press = recolor) ──
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    let isDrawingMode = activeTool == .pen
                        || activeTool == .straightLine
                        || activeTool == .marker
                    let isSel = isDrawingMode && selectedColorTag == i

                    PencilTipView(tipColor: pencilColor(at: i), isSelected: isSel)
                        .onTapGesture {
                            selectedColorTag = i
                            penColor = pencilColor(at: i)
                            if activeTool == .eraser || activeTool == .lasso {
                                activeTool = .pen
                            }
                        }
                        .onLongPressGesture(minimumDuration: 0.45) {
                            pickerColor = pencilColor(at: i)
                            longPressedPencilIndex = i
                        }
                        .popover(isPresented: Binding(
                            get: { longPressedPencilIndex == i },
                            set: { if !$0 { longPressedPencilIndex = nil } }
                        )) {
                            pencilColorPicker(slotIndex: i)
                        }
                }
            }
            .padding(.horizontal, 4)

            rowDivider

            // ── Drawing tools ─────────────────────────────────
            toolBtn(icon: "line.diagonal", tool: .straightLine)
            toolBtn(icon: "lasso",         tool: .lasso)
            toolBtn(icon: "eraser",        tool: .eraser)

            rowDivider

            // ── Ruler toggle ──────────────────────────────────
            rulerBtn

            rowDivider

            // ── Settings ──────────────────────────────────────
            Button { showSettings = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSettings) {
                NotepadSettingsView(notepad: notepad)
            }
        }
        .frame(height: 44)
    }

    // MARK: Pencil color-picker popover

    private let pencilSlotNames = ["Graphite", "Blueprint", "Amber", "PCB Green", "Warning Red"]

    @ViewBuilder
    private func pencilColorPicker(slotIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(pencilColor(at: slotIndex))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 0.5))
                Text(slotIndex < pencilSlotNames.count ? pencilSlotNames[slotIndex] : "Pencil \(slotIndex + 1)")
                    .font(.headline)
            }

            ColorPicker("Pencil color", selection: $pickerColor, supportsOpacity: false)
                .onChange(of: pickerColor) { _, newColor in
                    setPencilHex(newColor.hexString(), at: slotIndex)
                    // Live-update the canvas color if this slot is active.
                    if selectedColorTag == slotIndex { penColor = newColor }
                }

            Text("Long-press any pencil to recolor it again.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(minWidth: 230)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: Title field / label

    private var titleControl: some View {
        Group {
            if isEditingTitle {
                TextField("Title", text: $tempTitle)
                    .onSubmit(commitTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 120)
            } else {
                Text(notepad.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 120)
                    .onTapGesture {
                        tempTitle = notepad.title
                        isEditingTitle = true
                    }
            }
        }
    }

    private func commitTitle() {
        let t = tempTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { notepad.title = t; notepad.markEdited() }
        isEditingTitle = false
    }

    // MARK: Reusable sub-views

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 4)
    }

    private func toolBtn(icon: String, tool: DrawingTool) -> some View {
        let sel = activeTool == tool
        return Button { activeTool = sel ? .pen : tool } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(sel ? Color.accentColor : Color.secondary)
                .frame(width: 32, height: 32)
                .background(sel ? Color.accentColor.opacity(0.15) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private var rulerBtn: some View {
        Button { rulerActive.toggle() } label: {
            Image(systemName: rulerActive ? "ruler.fill" : "ruler")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(rulerActive ? Color.accentColor : Color.secondary)
                .frame(width: 32, height: 32)
                .background(rulerActive ? Color.accentColor.opacity(0.15) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
    #endif
}

// MARK: - Pencil Tip View + Shapes

#if os(iOS)
/// The visible portion of a pencil stored tip-down: tapered wood shaving + colored lead triangle.
/// Tap = select that color; long-press = open color picker.
private struct PencilTipView: View {
    let tipColor: Color
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Wood shaving (tapered)
            Rectangle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.79, green: 0.63, blue: 0.44),
                             Color(red: 0.65, green: 0.50, blue: 0.32)],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(width: 10, height: 4)
                .mask(TrapezoidMask())

            // Colored lead tip
            Rectangle()
                .fill(tipColor)
                .frame(width: 10, height: 11)
                .mask(TriangleTipMask())
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? tipColor.opacity(0.15) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isSelected ? tipColor : Color.clear, lineWidth: 1.5)
                )
        )
        .scaleEffect(isSelected ? 1.12 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

private struct TrapezoidMask: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.28
        return Path { p in
            p.move(to:    CGPoint(x: rect.minX,         y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX,         y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

private struct TriangleTipMask: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to:    CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}
#endif
