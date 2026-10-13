//
//  NotepadEditorView.swift
//  Tolerance
//
//  Custom two-row header:
//    Row 1 — mode tabs: Math (grid paper) | English (lined) | Draw (blank)
//    Row 2 — home · toggle sidebar · title · pencil tips · tools · ruler · settings
//
//  Home always returns to HomeView's top-level Home screen (not just back to
//  the enclosing book); the notebook side panel (ChapterSidebarView) is
//  always available while a note is open, so "back to this book's chapters"
//  is just a look at the sidebar rather than a separate nav action.
//
//  Pencil tips: tap to select, double-tap to open a color picker for that
//  slot, long-press to open a curved tool/color palette (RadialToolMenu) —
//  eraser/highlighter/line/shape on top, a scrollable strip of colors below.
//  Colors per slot persist for the session and update live if the slot is active.
//  Drawing state (activeTool, penColor, rulerActive) lives here so the toolbar
//  and the canvas share it through bindings.
//

import SwiftUI
import SwiftData
#if os(iOS)
import PencilKit
#endif

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
    var isSidebarOpen: Bool = true
    var onHome: () -> Void = {}
    var onToggleSidebar: () -> Void = {}
    var onUndoManagerReady: (UndoManager?) -> Void = { _ in }
    var requestedGraph: String? = nil
    var requestedGraphForce3D: Bool? = nil

    @State private var showSettings = false
    @State private var isEditingTitle = false
    @State private var tempTitle = ""

    // Drawing state — owned here, passed as bindings to CanvasWorkspace.
    #if os(iOS)
    @State private var activeTool: DrawingTool = .pen
    @State private var penColor: Color = Color(red: 0.15, green: 0.15, blue: 0.15)
    @State private var penWidth: Double = 3
    @State private var rulerActive: Bool = false

    // Pencil slot selection — persisted globally so it's the same across all notepads.
    @AppStorage("selectedPencilSlot") private var selectedColorTag: Int = 0

    // Per-slot pencil colors — persisted as hex strings so choices survive app launches.
    @AppStorage("pencilSlot0") private var pencilHex0: String = "#262626"  // Graphite
    @AppStorage("pencilSlot1") private var pencilHex1: String = "#173B9E"  // Blueprint
    @AppStorage("pencilSlot2") private var pencilHex2: String = "#D48008"  // Amber
    @AppStorage("pencilSlot3") private var pencilHex3: String = "#127038"  // PCB Green
    @AppStorage("pencilSlot4") private var pencilHex4: String = "#BD1414"  // Warning Red

    // Double-tap color-picker state
    @State private var longPressedPencilIndex: Int? = nil
    @State private var pickerColor: Color = .black

    // Calculator popup
    @State private var showCalculator = false

    // Box-to-Verify mode (Gemini Vision)
    @State private var isVerifyMode = false

    // Shape tool
    @State private var activeShapeKind: ShapeKind = .rectangle
    @State private var showShapePicker = false

    // Photo import (trigger passed down to CanvasWorkspace)
    @State private var showPhotoPicker = false

    // Export (Settings → General → Default Export Format)
    @AppStorage(GeneralPrefs.defaultExportFormat) private var exportFormatRaw = ExportFormat.pdf.rawValue
    @State private var exportedFileURL: URL? = nil
    @State private var showExportShare = false
    @State private var isExporting = false

    // AI Practice grading (Submit button — only shown when notepad.isAIPractice)
    @State private var isGradingPractice = false
    @State private var showGradingResults = false
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
            .sheet(isPresented: $showExportShare) {
                if let url = exportedFileURL {
                    ActivityView(activityItems: [url])
                }
            }
            .sheet(isPresented: $showGradingResults) {
                AIPracticeGradingResultsView(notepad: notepad)
            }
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
            penWidth: $penWidth,
            rulerActive: $rulerActive,
            isVerifyMode: $isVerifyMode,
            showPhotoPicker: $showPhotoPicker,
            activeShapeKind: activeShapeKind,
            onUndoManagerReady: onUndoManagerReady,
            requestedGraph: requestedGraph,
            requestedGraphForce3D: requestedGraphForce3D
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
            if notepad.isAIPractice {
                aiPracticeModeRow
            } else {
                modeTabRow
            }
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

    /// Replaces modeTabRow for AI Practice notepads — switching to Math/
    /// English/Draw would overwrite the worksheet's typed question layout,
    /// so there's no path back to any of those paper styles from here.
    private var aiPracticeModeRow: some View {
        Label("AI Practice", systemImage: "wand.and.stars")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
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

    // MARK: Tool row  (home · sidebar · title · pencil tips · tools · ruler · settings)

    // Fixed layout: home/sidebar-toggle/title always sit on the left, the
    // pencil/tool palette always on the right.
    private var toolRow: some View {
        HStack(spacing: 0) {
            leadingCluster
            Spacer(minLength: 6)
            trailingCluster
        }
        .frame(height: 44)
    }

    // ── Home · toggle sidebar · title ─────────────────────────
    private var leadingCluster: some View {
        HStack(spacing: 0) {
            Button(action: onHome) {
                Image(systemName: "house")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onToggleSidebar) {
                Text(isSidebarOpen ? "<" : ">")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            titleControl
        }
    }

    // ── Pencil tips · drawing tools · shape · photo · ruler · calculator · verify · export · settings ──
    private var trailingCluster: some View {
        HStack(spacing: 0) {
            // ── Pencil thickness (plain Pen tool only) ──────────
            if activeTool == .pen {
                penWidthSlider
                rowDivider
            }

            // ── Pencil tips (tap = select, double-tap = recolor) ──
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    let isDrawingMode = activeTool == .pen
                        || activeTool == .straightLine
                        || activeTool == .marker
                        || activeTool == .highlighter
                        || activeTool == .shape
                    let isSel = isDrawingMode && selectedColorTag == i

                    PencilTipView(tipColor: pencilColor(at: i), isSelected: isSel)
                        .onTapGesture {
                            selectedColorTag = i
                            penColor = pencilColor(at: i)
                            if activeTool == .eraser || activeTool == .lasso {
                                activeTool = .pen
                            }
                        }
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                pickerColor = pencilColor(at: i)
                                longPressedPencilIndex = i
                            }
                        )
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
            toolBtn(icon: "highlighter",   tool: .highlighter)
            toolBtn(icon: "line.diagonal", tool: .straightLine)
            toolBtn(icon: "lasso",         tool: .lasso)
            toolBtn(icon: "eraser",        tool: .eraser)

            rowDivider

            // ── Shape tool ────────────────────────────────────
            shapeBtn

            // ── Smart Draw (freehand → snapped line/arrow/shape) ─
            toolBtn(icon: "wand.and.rays", tool: .smartDraw)

            // ── Photo import ──────────────────────────────────
            Button { showPhotoPicker = true } label: {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            rowDivider

            // ── Ruler toggle ──────────────────────────────────
            rulerBtn

            rowDivider

            // Calculator
            Button { showCalculator.toggle() } label: {
                Image(systemName: "sum")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(showCalculator ? Color.accentColor : Color.secondary)
                    .frame(width: 32, height: 32)
                    .background(showCalculator ? Color.accentColor.opacity(0.15) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showCalculator) {
                ScientificCalculatorView()
                    .presentationCompactAdaptation(.popover)
            }

            rowDivider

            // ── Verify (Box-to-Verify / Gemini Vision) ───────────────
            Button { isVerifyMode.toggle() } label: {
                Image(systemName: "viewfinder.rectangular")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isVerifyMode ? Color.accentColor : Color.secondary)
                    .frame(width: 32, height: 32)
                    .background(isVerifyMode ? Color.accentColor.opacity(0.15) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)

            // ── Export ────────────────────────────────────────
            Button { exportNotepad() } label: {
                Group {
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(isExporting)

            // ── Submit for grading (AI Practice notepads only) ──
            if notepad.isAIPractice {
                rowDivider

                Button { Task { await submitPractice() } } label: {
                    if isGradingPractice {
                        ProgressView()
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.green)
                            .frame(width: 32, height: 32)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isGradingPractice)
            }

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

    // MARK: AI Practice grading (Submit button)

    /// Crops just the student's answer ink for each question directly out of
    /// the page's stored PKDrawing (independent of scroll position — see
    /// AIPracticeQuestion), grades each crop on-device (FoundationModels
    /// multimodal prompting — no network call, no rate limit) along with its
    /// question text, and records the verdict/feedback before showing results.
    private func submitPractice() async {
        guard let page = notepad.orderedPages.first else { return }
        isGradingPractice = true
        defer { isGradingPractice = false }

        let drawing = page.drawingData.isEmpty
            ? PKDrawing()
            : (try? PKDrawing(data: page.drawingData)) ?? PKDrawing()

        for question in notepad.orderedAIPracticeQuestions {
            let rect = CGRect(
                x: 0, y: question.answerYStart,
                width: AIPracticeGenerator.contentWidth,
                height: question.answerYEnd - question.answerYStart
            )
            let image = drawing.image(from: rect, scale: 2)
            guard let cgImage = image.cgImage else { continue }

            guard #available(iOS 27.0, *) else {
                question.isCorrect = nil
                question.gradeFeedback = "Grading needs iOS 27 or later."
                continue
            }

            do {
                let (isCorrect, feedback) = try await AIPracticeGenerator.grade(image: cgImage, question: question.text)
                question.isCorrect = isCorrect
                question.gradeFeedback = feedback
            } catch {
                question.isCorrect = nil
                question.gradeFeedback = error.localizedDescription
            }
        }

        showGradingResults = true
    }

    // MARK: Export (Settings → General → Default Export Format)

    /// Rasterizing the whole drawing and re-encoding it as PDF/PNG used to
    /// run synchronously on the main thread inside the button tap, so the
    /// UI froze (no spinner, nothing) until it finished — which from the
    /// outside looked indistinguishable from the share sheet just being
    /// slow. Moving the actual rendering off the main thread, and showing
    /// a spinner on the export button in the meantime, fixes both: the
    /// share sheet itself was never the bottleneck.
    private func exportNotepad() {
        guard let page = notepad.orderedPages.first else { return }
        let drawingData = page.drawingData
        let fileName = notepad.title.isEmpty ? "Notepad" : notepad.title
        let format = ExportFormat(rawValue: exportFormatRaw) ?? .pdf

        isExporting = true
        Task.detached(priority: .userInitiated) {
            let url = Self.renderExportFile(drawingData: drawingData, fileName: fileName, format: format)
            await MainActor.run {
                isExporting = false
                if let url {
                    exportedFileURL = url
                    showExportShare = true
                }
            }
        }
    }

    private nonisolated static func renderExportFile(drawingData: Data, fileName: String, format: ExportFormat) -> URL? {
        let drawing = drawingData.isEmpty
            ? PKDrawing()
            : (try? PKDrawing(data: drawingData)) ?? PKDrawing()

        let bounds = drawing.bounds.isEmpty
            ? CGRect(x: 0, y: 0, width: 1000, height: 1400)
            : drawing.bounds.insetBy(dx: -20, dy: -20)
        let image = drawing.image(from: bounds, scale: 2)

        do {
            let url: URL
            switch format {
            case .pdf:
                url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(fileName).appendingPathExtension("pdf")
                let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: bounds.size))
                let data = renderer.pdfData { ctx in
                    ctx.beginPage()
                    image.draw(in: CGRect(origin: .zero, size: bounds.size))
                }
                try data.write(to: url, options: .atomic)
            case .png:
                url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(fileName).appendingPathExtension("png")
                guard let data = image.pngData() else { return nil }
                try data.write(to: url, options: .atomic)
            }
            return url
        } catch {
            // Best-effort export; if writing the temp file fails there's nothing to share.
            return nil
        }
    }

    // MARK: Reusable sub-views

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 4)
    }

    /// Only shown while the plain Pen tool is active — the other drawing
    /// tools (marker, highlighter, straight line, shape) have their own
    /// fixed/derived widths and aren't affected by this.
    private var penWidthSlider: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil.tip")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Slider(value: $penWidth, in: 1...40)
                .frame(width: 270)
            Image(systemName: "pencil.tip")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
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

    private var shapeBtn: some View {
        let sel = activeTool == .shape
        return Button {
            if sel {
                activeTool = .pen
            } else {
                showShapePicker = true
            }
        } label: {
            Image(systemName: activeShapeKind.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(sel ? Color.accentColor : Color.secondary)
                .frame(width: 32, height: 32)
                .background(sel ? Color.accentColor.opacity(0.15) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showShapePicker) {
            ShapePickerPopover(activeKind: $activeShapeKind) { kind in
                activeShapeKind = kind
                activeTool = .shape
                showShapePicker = false
            }
            .presentationCompactAdaptation(.popover)
        }
    }
    #endif
}

// MARK: - Export share sheet

#if os(iOS)
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif

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

private struct ShapePickerPopover: View {
    @Binding var activeKind: ShapeKind
    let onSelect: (ShapeKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Shape")
                .font(.headline)
                .padding(.bottom, 4)
            ForEach(ShapeKind.allCases, id: \.self) { kind in
                Button { onSelect(kind) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: kind.systemImage)
                            .frame(width: 22, alignment: .center)
                        Text(kind.displayName)
                    }
                    .foregroundStyle(activeKind == kind ? Color.accentColor : Color.primary)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(minWidth: 170)
    }
}
#endif
