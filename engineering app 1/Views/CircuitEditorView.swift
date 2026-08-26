//
//  CircuitEditorView.swift
//  Tolerance
//
//  Full-screen circuit diagram editor on a blank (no-grid) white canvas.
//  Modes: select · wire · erase · place<type>
//  Toolbar is compact (icon-only palette, 36 pt height) to maximise canvas space.
//  Generated circuits are placed at the centre of the visible viewport and the
//  scroll position is reset so they appear exactly centred on screen.
//

#if os(iOS)
import SwiftUI
import SwiftData
import FoundationModels

// MARK: - Editor mode

private enum CircuitEditorMode: Equatable {
    case select
    case place(CircuitComponentType)
    case wire
    case erase
}

// MARK: - @Generable types for AI circuit generation

@Generable
struct GeneratedCircuitLayout {
    @Guide(description: "All components in the circuit, starting with the power source (battery).")
    var components: [GeneratedCircuitItem]
}

@Generable
struct GeneratedCircuitItem {
    @Guide(description: """
    Component type — must be one of exactly:
    resistor | battery | capacitor | inductor | led | switchComp | ground | voltmeter | ammeter
    """)
    var type: String

    @Guide(description: "Label such as R1, V1, C1, L1, D1")
    var label: String

    @Guide(description: """
    Numeric value with NO units (e.g. 100 for 100Ω, 9 for 9V, 47 for 47μF).
    Use 0 for components that don't have a numeric value (ground, switch).
    """)
    var value: Double

    @Guide(description: "True if this component type normally carries a numeric value.")
    var hasValue: Bool

    @Guide(description: """
    Parallel branch index. Use 0 for components in the main series path (battery, switches, meters).
    For parallel branches assign each branch a unique integer starting at 1.
    Example: two resistors in parallel → R1 gets branch=1, R2 gets branch=2.
    All components sharing the same junction get the same non-zero branch number only if
    they are literally in series WITHIN that branch.
    """)
    var branch: Int
}

// MARK: - Main view

struct CircuitEditorView: View {
    @Bindable var diagram: CircuitDiagram
    @Environment(\.modelContext) private var modelContext
    var onBack: () -> Void = {}

    // Local edit state — synced to diagram on every mutation
    @State private var components: [CircuitComponent] = []
    @State private var wires:      [CircuitWire]      = []

    @State private var mode:       CircuitEditorMode = .select
    @State private var selectedID: UUID?              = nil

    // Wire-drawing live preview
    @State private var wireAnchor: CGPoint? = nil
    @State private var wireTip:    CGPoint? = nil

    // Viewport size captured by GeometryReader (used for centred generation)
    @State private var viewportSize: CGSize = CGSize(width: 800, height: 600)
    // Non-nil after generation so ScrollViewReader can scroll to it
    @State private var generatedAnchor: CGPoint? = nil

    // Value editor
    @State private var showValueEditor = false
    @State private var editingComp:    CircuitComponent? = nil
    @State private var valueText = ""

    // AI analysis
    @State private var showAnalysis = false
    @State private var analysisText = ""
    @State private var isAnalyzing  = false

    // Animation
    @State private var isAnimating = false
    @State private var wireFlow: [UUID: Bool] = [:]  // true = start→end, false = end→start

    // Setup sheet (shown on first open when canvas is empty)
    @State private var showSetup    = false
    @State private var setupPhase:  SetupPhase = .choice
    @State private var setupPrompt  = ""
    @State private var isGenerating = false

    private enum SetupPhase { case choice, aiInput }

    private let canvasW: CGFloat = 3000
    private let canvasH: CGFloat = 2000

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            circuitCanvas
        }
        .background(Color(red: 0.07, green: 0.08, blue: 0.10))
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
            components = diagram.loadComponents()
            wires      = diagram.loadWires()
            if components.isEmpty { showSetup = true }
        }
        .sheet(isPresented: $showSetup)       { setupSheet }
        .sheet(isPresented: $showValueEditor) { valueEditorSheet }
        .sheet(isPresented: $showAnalysis)    { analysisSheet }
        .onChange(of: isAnimating) { _, on in if on { wireFlow = buildFlowDirections() } }
    }

    // MARK: - Toolbar (compact: 36 pt, icon-only palette)

    private var toolbar: some View {
        HStack(spacing: 0) {
            // Back
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(diagram.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: 110)

            vDivider

            // Select
            modeBtn(icon: "arrow.up.left.and.arrow.down.right", active: mode == .select) {
                mode = .select
            }
            // Wire
            modeBtn(icon: "line.diagonal", active: mode == .wire) {
                mode = mode == .wire ? .select : .wire
            }
            // Erase
            modeBtn(icon: "eraser", active: mode == .erase) {
                mode = mode == .erase ? .select : .erase
            }

            vDivider

            // Component palette — icon-only, scrollable
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(CircuitComponentType.allCases, id: \.self) { type in
                        paletteBtn(type)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: 300)

            vDivider

            // Rotate selected
            Button {
                guard let id = selectedID,
                      let i = components.firstIndex(where: { $0.id == id }) else { return }
                components[i].rotation = (components[i].rotation + 90)
                    .truncatingRemainder(dividingBy: 360)
                saveChanges()
            } label: {
                Image(systemName: "rotate.right")
                    .foregroundStyle(selectedID != nil ? Color.accentColor : Color.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(selectedID == nil)

            // Delete selected
            Button {
                guard let id = selectedID else { return }
                components.removeAll { $0.id == id }
                selectedID = nil
                saveChanges()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(selectedID != nil ? Color.red : Color.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(selectedID == nil)

            vDivider

            // Animate current flow
            Button {
                isAnimating.toggle()
            } label: {
                Label(isAnimating ? "Stop" : "Animate", systemImage: isAnimating ? "stop.fill" : "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isAnimating ? Color.yellow : Color.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(isAnimating ? Color.yellow.opacity(0.18) : Color.clear, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            vDivider

            // AI analyse
            Button { Task { await runAnalysis() } } label: {
                Label("Analyze", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(Color.purple.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 5)
        }
        .frame(height: 36)
        .background(.bar)
    }

    private var vDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 3)
    }

    private func modeBtn(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
                .background(active ? Color.accentColor.opacity(0.13) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func paletteBtn(_ type: CircuitComponentType) -> some View {
        let active = { if case .place(let t) = mode { return t == type } else { return false } }()
        return Button {
            mode = active ? .select : .place(type)
        } label: {
            Image(systemName: type.sfIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .frame(width: 30, height: 30)
                .background(active ? Color.accentColor.opacity(0.13) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(type.rawValue)
    }

    // MARK: - Canvas

    private var circuitCanvas: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    ZStack(alignment: .topLeading) {

                        // Background: place / deselect / wire-draw / erase-wire
                        Color(red: 0.07, green: 0.08, blue: 0.10)
                            .frame(width: canvasW, height: canvasH)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { v in
                                        guard case .wire = mode else { return }
                                        if wireAnchor == nil { wireAnchor = v.startLocation }
                                        wireTip = v.location
                                    }
                                    .onEnded { v in
                                        let dist = hypot(v.translation.width, v.translation.height)
                                        switch mode {
                                        case .select:
                                            if dist < 6 { selectedID = nil }
                                        case .place(let type):
                                            addComponent(type, at: v.startLocation)
                                            mode = .select
                                        case .wire:
                                            if dist > 6, let anchor = wireAnchor {
                                                wires.append(CircuitWire(
                                                    start: CircuitPoint(anchor),
                                                    end:   CircuitPoint(v.location)
                                                ))
                                                saveChanges()
                                            }
                                            wireAnchor = nil; wireTip = nil
                                        case .erase:
                                            if dist < 20 {
                                                eraseNearestWire(at: v.startLocation)
                                            }
                                        }
                                    }
                            )

                        // Wires + preview
                        Canvas { ctx, size in
                            // Committed wires
                            var path = Path()
                            for w in wires {
                                path.move(to: w.start.cgPoint)
                                path.addLine(to: w.end.cgPoint)
                            }
                            ctx.stroke(path, with: .color(.white),
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round))

                            // Live wire preview
                            if let anchor = wireAnchor, let tip = wireTip {
                                var preview = Path()
                                preview.move(to: anchor)
                                preview.addLine(to: tip)
                                ctx.stroke(preview, with: .color(.blue.opacity(0.7)),
                                           style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                                              dash: [8, 4]))
                            }
                        }
                        .frame(width: canvasW, height: canvasH)
                        .allowsHitTesting(false)

                        // Current-flow animation overlay
                        if isAnimating {
                            TimelineView(.animation) { tl in
                                Canvas { ctx, _ in
                                    let t = tl.date.timeIntervalSinceReferenceDate
                                    for wire in wires {
                                        // Respect current-flow direction so all dots move one way
                                        let forward = wireFlow[wire.id] ?? true
                                        let a = forward ? wire.start.cgPoint : wire.end.cgPoint
                                        let b = forward ? wire.end.cgPoint   : wire.start.cgPoint
                                        let len = hypot(b.x - a.x, b.y - a.y)
                                        guard len > 8 else { continue }
                                        let speed = animSpeed(near: wire)
                                        let spacing: CGFloat = 22
                                        let phase = CGFloat(t * speed * 55)
                                            .truncatingRemainder(dividingBy: spacing)
                                        var d = phase
                                        while d < len {
                                            let frac = d / len
                                            let px = a.x + (b.x - a.x) * frac
                                            let py = a.y + (b.y - a.y) * frac
                                            let r: CGFloat = speed > 1.5 ? 4 : speed < 0.5 ? 2 : 3
                                            ctx.fill(
                                                Path(ellipseIn: CGRect(x: px-r, y: py-r,
                                                                       width: r*2, height: r*2)),
                                                with: .color(Color.yellow.opacity(0.9))
                                            )
                                            d += spacing
                                        }
                                    }
                                }
                                .frame(width: canvasW, height: canvasH)
                                .allowsHitTesting(false)
                            }
                        }

                        // Components
                        ForEach(components) { comp in
                            CircuitSymbolView(component: comp, isSelected: selectedID == comp.id)
                                .position(comp.position)
                                .gesture(
                                    DragGesture(minimumDistance: 4)
                                        .onChanged { v in
                                            guard case .select = mode else { return }
                                            moveComponent(id: comp.id, to: v.location)
                                        }
                                        .onEnded { _ in saveChanges() }
                                )
                                .onTapGesture {
                                    if case .erase = mode {
                                        components.removeAll { $0.id == comp.id }
                                        if selectedID == comp.id { selectedID = nil }
                                        saveChanges()
                                    } else {
                                        withAnimation(.spring(response: 0.2)) {
                                            if selectedID == comp.id && comp.type.hasValue {
                                                editingComp = comp
                                                valueText = comp.value.map {
                                                    $0 == $0.rounded() && abs($0) < 1e6
                                                        ? "\(Int($0))" : String(format: "%.4g", $0)
                                                } ?? ""
                                                showValueEditor = true
                                            } else {
                                                selectedID = comp.id == selectedID ? nil : comp.id
                                            }
                                        }
                                    }
                                }
                        }

                        // Invisible scroll-to anchor after AI generation
                        if let anchor = generatedAnchor {
                            Color.clear
                                .frame(width: 1, height: 1)
                                .id("generatedAnchor")
                                .position(anchor)
                        }
                    }
                }
                .background(Color(red: 0.07, green: 0.08, blue: 0.10))
                .environment(\.colorScheme, .dark)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0 }
                .onChange(of: generatedAnchor) { _, pt in
                    guard pt != nil else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            proxy.scrollTo("generatedAnchor", anchor: .center)
                        }
                    }
                }
        }
    }

    // MARK: - Setup sheet

    private var setupSheet: some View {
        NavigationStack {
            Group {
                switch setupPhase {
                case .choice: setupChoiceView
                case .aiInput: setupAIView
                }
            }
            .navigationTitle("New Circuit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { showSetup = false }
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isGenerating)
    }

    private var setupChoiceView: some View {
        VStack(spacing: 22) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.yellow)

            Text("How do you want to start?")
                .font(.title3.weight(.semibold))

            VStack(spacing: 12) {
                choiceCard(icon: "wand.and.sparkles", color: .purple,
                           title: "Generate with AI",
                           sub: "Describe your circuit — AI places and wires the components") {
                    setupPhase = .aiInput
                }
                choiceCard(icon: "hand.draw", color: .blue,
                           title: "Build Yourself",
                           sub: "Pick components from the palette and draw your own wires") {
                    showSetup = false
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 24)
    }

    private func choiceCard(icon: String, color: Color, title: String,
                            sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 46, height: 46)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.semibold))
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var setupAIView: some View {
        VStack(spacing: 16) {
            Text("Describe your circuit")
                .font(.headline)
            Text("Example: \"9 V battery with 100 Ω, 220 Ω, and 470 Ω resistors in series\"")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextEditor(text: $setupPrompt)
                .frame(height: 80)
                .font(.body)
                .padding(6)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 24)

            Button {
                Task { await generateFromPrompt() }
            } label: {
                Group {
                    if isGenerating { ProgressView().tint(.white) }
                    else { Label("Generate", systemImage: "sparkles") }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    setupPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating
                        ? Color.secondary : Color.purple,
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(setupPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
            .padding(.horizontal, 24)

            Button("Back") { setupPhase = .choice }
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
    }

    // MARK: - Value editor sheet

    @ViewBuilder
    private var valueEditorSheet: some View {
        if let comp = editingComp {
            NavigationStack {
                VStack(spacing: 22) {
                    CircuitSymbolView(component: comp, isSelected: false)
                        .scaleEffect(1.5)
                        .frame(height: 90)

                    HStack(spacing: 8) {
                        TextField("Value", text: $valueText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.title3, design: .monospaced))
                        if !comp.unit.isEmpty {
                            Text(comp.unit)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 32)
                        }
                    }
                    .padding(.horizontal, 32)

                    Text("Enter the \(comp.type.rawValue.lowercased()) value"
                         + (comp.unit.isEmpty ? "" : " in \(comp.unit)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)
                .navigationTitle(comp.label)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showValueEditor = false; editingComp = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let i = components.firstIndex(where: { $0.id == comp.id }) {
                                components[i].value = Double(valueText)
                            }
                            saveChanges()
                            showValueEditor = false; editingComp = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Analysis sheet

    private var analysisSheet: some View {
        NavigationStack {
            ScrollView {
                if isAnalyzing {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Analyzing circuit…")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    Text(analysisText.isEmpty
                         ? "Add components with values, then tap Analyze."
                         : analysisText)
                        .font(.body)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Circuit Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showAnalysis = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !isAnalyzing {
                        Button { Task { await runAnalysis() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Helpers

    private func nextLabel(for type: CircuitComponentType) -> String {
        let n = components.filter { $0.type == type }.count
        return "\(type.prefix)\(n + 1)"
    }

    private func addComponent(_ type: CircuitComponentType, at pt: CGPoint) {
        var comp = CircuitComponent(type: type,
                                   x: Double(pt.x), y: Double(pt.y),
                                   label: nextLabel(for: type))
        if type == .battery  { comp.value = 9 }
        if type == .resistor { comp.value = 100 }
        components.append(comp)
        selectedID = comp.id
        saveChanges()
    }

    private func moveComponent(id: UUID, to pt: CGPoint) {
        guard let i = components.firstIndex(where: { $0.id == id }) else { return }
        components[i].x = Double(pt.x)
        components[i].y = Double(pt.y)
    }

    private func eraseNearestWire(at point: CGPoint) {
        let threshold: CGFloat = 22
        guard let (idx, wire) = wires.enumerated().min(by: {
            distToSegment(point, $0.element.start.cgPoint, $0.element.end.cgPoint)
            < distToSegment(point, $1.element.start.cgPoint, $1.element.end.cgPoint)
        }) else { return }
        if distToSegment(point, wire.start.cgPoint, wire.end.cgPoint) < threshold {
            wires.remove(at: idx)
            saveChanges()
        }
    }

    private func distToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx*dx + dy*dy
        if lenSq == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x)*dx + (p.y - a.y)*dy) / lenSq))
        return hypot(p.x - (a.x + t*dx), p.y - (a.y + t*dy))
    }

    private func saveChanges() {
        diagram.save(components: components)
        diagram.save(wires: wires)
    }

    private var isAIAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    // Strip LaTeX remnants so the text is always human-readable.
    private func cleanAnalysisText(_ raw: String) -> String {
        var s = raw
        // Math delimiters
        for token in ["\\(", "\\)", "\\[", "\\]"] {
            s = s.replacingOccurrences(of: token, with: "")
        }
        // Common LaTeX commands
        let replacements: [(String, String)] = [
            ("\\times",  "×"),
            ("\\cdot",   "·"),
            ("\\div",    "÷"),
            ("\\approx", "≈"),
            ("\\Omega",  "Ω"),
            ("\\mu",     "μ"),
            ("\\,",      " "),
            ("\\;",      " "),
            ("\\:",      " "),
            ("\\!",      ""),
            ("\\text{",  ""),
            ("\\mathrm{",""),
            ("\\mathbf{",""),
            ("\\left(",  "("),
            ("\\right)", ")"),
            ("\\left[",  "["),
            ("\\right]", "]"),
        ]
        for (latex, plain) in replacements {
            s = s.replacingOccurrences(of: latex, with: plain)
        }
        // Remove stray closing braces left by \text{} etc.
        // Also convert _{digit} → subscript unicode
        let subDigits = ["₀","₁","₂","₃","₄","₅","₆","₇","₈","₉"]
        for (i, sub) in subDigits.enumerated() {
            s = s.replacingOccurrences(of: "_{\(i)}", with: sub)
            s = s.replacingOccurrences(of: "_\(i)",   with: sub)
        }
        // Superscript ² ³ for common exponents
        s = s.replacingOccurrences(of: "^{2}", with: "²")
        s = s.replacingOccurrences(of: "^2",   with: "²")
        s = s.replacingOccurrences(of: "^{3}", with: "³")
        s = s.replacingOccurrences(of: "^3",   with: "³")
        // Remove leftover lone braces
        s = s.replacingOccurrences(of: "{", with: "")
        s = s.replacingOccurrences(of: "}", with: "")
        // Collapse multiple spaces
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - AI: generate circuit from prompt

    private func generateFromPrompt() async {
        isGenerating = true
        defer { isGenerating = false }

        guard isAIAvailable else { showSetup = false; return }

        let instructions = """
        You are a circuit schematic assistant. Output a flat list of ALL components in the circuit.

        SERIES components (battery, switches, meters, and any single-path component): set branch=0.
        PARALLEL branches: each distinct parallel branch gets a unique branch number ≥ 1.
          - Two resistors in parallel → R1 has branch=1, R2 has branch=2.
          - Three resistors in parallel → branch=1, branch=2, branch=3.
          - If a parallel branch itself contains multiple series components, give them the SAME branch number.

        Use ONLY these type strings: resistor, battery, capacitor, inductor, led, switchComp, ground, voltmeter, ammeter.
        Provide sensible default values. Always include the battery with branch=0.
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let resp = try await session.respond(
                to: "Create this circuit: \(setupPrompt)",
                generating: GeneratedCircuitLayout.self
            )
            placeGeneratedCircuit(resp.content.components)
        } catch { }

        showSetup = false
    }

    // Place components centred in the visible viewport, supporting series and parallel topologies.
    private func placeGeneratedCircuit(_ items: [GeneratedCircuitItem]) {
        guard !items.isEmpty else { return }
        let cx = viewportSize.width  / 2
        let cy = viewportSize.height / 2

        let seriesItems   = items.filter { $0.branch == 0 }
        let parallelGroups = Dictionary(grouping: items.filter { $0.branch > 0 }, by: { $0.branch })

        var placed:   [CircuitComponent] = []
        var newWires: [CircuitWire]      = []

        func w(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
            newWires.append(CircuitWire(start: CircuitPoint(x: Double(x1), y: Double(y1)),
                                        end:   CircuitPoint(x: Double(x2), y: Double(y2))))
        }

        func comp(_ item: GeneratedCircuitItem, x: CGFloat, y: CGFloat) -> CircuitComponent {
            let type = CircuitComponentType.allCases.first {
                $0.rawValue.lowercased() == item.type.lowercased()
            } ?? .resistor
            var c = CircuitComponent(type: type, x: Double(x), y: Double(y),
                                     label: item.label.isEmpty ? diagram.nextLabel(for: type) : item.label)
            if item.hasValue && item.value != 0 { c.value = item.value }
            return c
        }

        if parallelGroups.isEmpty {
            // ── Pure series ──
            let step: CGFloat = 180
            let x0 = cx - step * CGFloat(items.count - 1) / 2
            for (i, item) in items.enumerated() {
                placed.append(comp(item, x: x0 + step * CGFloat(i), y: cy))
            }
            for i in 0..<placed.count - 1 {
                w(placed[i].x + 44, placed[i].y, placed[i+1].x - 44, placed[i+1].y)
            }
            if placed.count > 1 {
                let loopY = cy + 110
                let fx = CGFloat(placed.first!.x) - 44, lx = CGFloat(placed.last!.x) + 44
                w(fx, cy, fx, loopY); w(fx, loopY, lx, loopY); w(lx, loopY, lx, cy)
            }
        } else {
            // ── Series + parallel ──
            let nBranches     = parallelGroups.count
            let branchSpacing: CGFloat = 90
            let parallelW:     CGFloat = 220
            let jLX = cx - parallelW / 2
            let jRX = cx + parallelW / 2
            let seriesStep:   CGFloat = 160

            // Place series items to the left of the parallel block
            let seriesX0 = jLX - seriesStep * CGFloat(max(seriesItems.count, 1))
            for (i, item) in seriesItems.enumerated() {
                placed.append(comp(item, x: seriesX0 + seriesStep * (CGFloat(i) + 0.5), y: cy))
            }

            // Series wires + wire to left junction
            for i in 0..<placed.count - 1 {
                w(placed[i].x + 44, placed[i].y, placed[i+1].x - 44, placed[i+1].y)
            }
            if let last = placed.last {
                w(last.x + 44, last.y, jLX, cy)
            }

            // Parallel branches
            let sortedBranch = parallelGroups.keys.sorted()
            for (bi, key) in sortedBranch.enumerated() {
                let branchComps = parallelGroups[key]!
                let branchY = cy + (CGFloat(bi) - CGFloat(nBranches - 1) / 2) * branchSpacing
                let bStep   = parallelW / CGFloat(branchComps.count + 1)

                // Vertical wires from main line to branch
                w(jLX, cy, jLX, branchY)
                w(jRX, branchY, jRX, cy)

                // Components in branch + horizontal wires
                var lastX: CGFloat = jLX
                for (ci, item) in branchComps.enumerated() {
                    let bx = jLX + bStep * CGFloat(ci + 1)
                    let c = comp(item, x: bx, y: branchY)
                    placed.append(c)
                    w(lastX, branchY, bx - 44, branchY)
                    lastX = bx + 44
                }
                w(lastX, branchY, jRX, branchY)
            }

            // Return loop from jRX back to start
            let totalH  = CGFloat(nBranches - 1) * branchSpacing
            let loopY   = cy + totalH / 2 + 80
            let firstX  = placed.isEmpty ? jLX - 44 : CGFloat(placed.first!.x) - 44
            w(jRX, cy, jRX + 60, cy)
            w(jRX + 60, cy, jRX + 60, loopY)
            w(jRX + 60, loopY, firstX, loopY)
            w(firstX, loopY, firstX, cy)
        }

        components = placed
        wires      = newWires
        saveChanges()
        generatedAnchor = CGPoint(x: cx, y: cy)
    }

    // MARK: - AI: analyse circuit

    private func runAnalysis() async {
        analysisText = ""
        isAnalyzing  = true
        showAnalysis = true

        let snap = components
        guard !snap.isEmpty else { isAnalyzing = false; return }

        let desc = snap.map { c in
            var s = "• \(c.label) (\(c.type.rawValue))"
            if c.value != nil { s += " = \(c.valueString)" }
            return s
        }.joined(separator: "\n")

        guard isAIAvailable else {
            analysisText = "On-device AI unavailable.\n\nComponents:\n\(desc)"
            isAnalyzing = false; return
        }

        let instructions = """
        You are a circuit analyst. Write your entire response in plain English — readable by a student on screen.

        STRICT FORMATTING RULES — follow every one exactly:
        1. NO LaTeX at all. Never use \\( \\) \\[ \\] \\frac{} \\text{} \\cdot \\times or any backslash command.
        2. For numbered labels use Unicode subscript digits: R₁ R₂ V₁ V₂ I₁ P₁ C₁ L₁
           (subscript digits are ₀₁₂₃₄₅₆₇₈₉ — use them for every subscript number).
        3. Write every formula as a plain one-line equation:
              R_total = R₁ + R₂ = 100 + 220 = 320 Ω
        4. Multiplication: use ×.  Division: use /.  Do not use dots or other symbols.
        5. Units: write directly after the number with a space — 320 Ω, 9 V, 28.1 mA, 2.66 W.
        6. Section headers: short uppercase label followed by a colon on its own line, e.g.  TOTAL RESISTANCE:
        7. Be concise — one or two lines per step. No filler sentences.

        Compute all of the following that apply:
        - Series resistors: R_total = R₁ + R₂ + … then if a battery exists compute I = V / R_total
        - Voltage drop across each resistor: V₁ = I × R₁, V₂ = I × R₂, etc.
        - Power per resistor: P₁ = I² × R₁, and total power P_total = V × I
        - Parallel resistors: 1/R_total = 1/R₁ + 1/R₂ + … then R_total = result
        - Series capacitors: 1/C_total = 1/C₁ + 1/C₂ + …
        - Parallel capacitors: C_total = C₁ + C₂ + …
        - Inductors: same addition rules as resistors
        If you cannot tell series vs parallel from the list, compute the series case first, then the parallel case.
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let resp    = try await session.respond(to: "Analyze this circuit:\n\(desc)")
            analysisText = cleanAnalysisText(resp.content)
        } catch {
            analysisText = "Analysis failed: \(error.localizedDescription)\n\nCircuit:\n\(desc)"
        }

        isAnalyzing = false
    }

    // BFS from battery + terminal to assign a consistent current-flow direction
    // to every wire. Returns true = flow start→end, false = flow end→start.
    private func buildFlowDirections() -> [UUID: Bool] {
        var dir = [UUID: Bool]()
        let threshold: CGFloat = 60

        // Locate battery and its + terminal (right side at rotation 0; adjust for rotation)
        guard let battery = components.first(where: { $0.type == .battery }) else {
            // No battery: default all forward
            return Dictionary(uniqueKeysWithValues: wires.map { ($0.id, true) })
        }
        let rad = battery.rotation * .pi / 180
        let posX = battery.x + 44 * cos(rad)
        let posY = battery.y + 44 * sin(rad)
        let seed = CGPoint(x: posX, y: posY)

        // BFS: start from wires touching the + terminal
        var frontier: [CGPoint] = []
        for wire in wires {
            let s = wire.start.cgPoint, e = wire.end.cgPoint
            if hypot(seed.x - s.x, seed.y - s.y) < threshold {
                dir[wire.id] = true; frontier.append(e)
            } else if hypot(seed.x - e.x, seed.y - e.y) < threshold {
                dir[wire.id] = false; frontier.append(s)
            }
        }

        // Expand BFS through connected wire endpoints
        var visited = Set(dir.keys)
        while !frontier.isEmpty {
            let pt = frontier.removeFirst()
            for wire in wires where !visited.contains(wire.id) {
                let s = wire.start.cgPoint, e = wire.end.cgPoint
                if hypot(pt.x - s.x, pt.y - s.y) < threshold {
                    dir[wire.id] = true; visited.insert(wire.id); frontier.append(e)
                } else if hypot(pt.x - e.x, pt.y - e.y) < threshold {
                    dir[wire.id] = false; visited.insert(wire.id); frontier.append(s)
                }
            }
        }

        // Fallback for disconnected wires
        for wire in wires where dir[wire.id] == nil { dir[wire.id] = true }
        return dir
    }

    // Returns dot speed for a wire based on proximity to component types.
    private func animSpeed(near wire: CircuitWire) -> Double {
        let mx = (wire.start.x + wire.end.x) / 2
        let my = (wire.start.y + wire.end.y) / 2
        for comp in components {
            let d = hypot(comp.x - mx, comp.y - my)
            if d < 90 {
                switch comp.type {
                case .resistor:  return 0.3
                case .battery:   return 2.5
                case .led:       return 1.5
                case .capacitor: return 0.08
                case .inductor:  return 0.5
                default:         return 1.0
                }
            }
        }
        return 1.0
    }
}

// MARK: - Circuit symbol view

struct CircuitSymbolView: View {
    let component: CircuitComponent
    let isSelected: Bool

    private let W: CGFloat = 88
    private let H: CGFloat = 50

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                CircuitSymbolDrawer.draw(component: component, in: ctx, size: size)
            }
            .frame(width: W, height: H)
            .rotationEffect(.degrees(component.rotation))

            Text(labelText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize()
                .frame(maxWidth: W + 20)
                .offset(y: H / 2 + 12)
        }
        .frame(width: W + 20, height: H + 30)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1.5)
                    .frame(width: W + 12, height: H + 12)
            }
        }
        .contentShape(Rectangle())
    }

    private var labelText: String {
        component.value != nil
            ? "\(component.label): \(component.valueString)"
            : component.label
    }
}

// MARK: - Symbol drawing

enum CircuitSymbolDrawer {
    static func draw(component: CircuitComponent, in ctx: GraphicsContext, size: CGSize) {
        let cx = size.width / 2, cy = size.height / 2
        let tw = size.width / 2 - 2

        switch component.type {
        case .resistor:   drawResistor(ctx, cx, cy, tw)
        case .battery:    drawBattery(ctx, cx, cy, tw)
        case .capacitor:  drawCapacitor(ctx, cx, cy, tw)
        case .inductor:   drawInductor(ctx, cx, cy, tw)
        case .led:        drawLED(ctx, cx, cy, tw)
        case .switchComp: drawSwitch(ctx, cx, cy, tw, closed: component.isClosed)
        case .ground:     drawGround(ctx, cx, cy)
        case .voltmeter:  drawMeter(ctx, cx, cy, tw, label: "V")
        case .ammeter:    drawMeter(ctx, cx, cy, tw, label: "A")
        }
    }

    private static let wire = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)

    private static func drawResistor(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ tw: CGFloat) {
        let bw: CGFloat = 28; let bh: CGFloat = 16
        var leads = Path()
        leads.move(to: CGPoint(x: cx - tw,   y: cy)); leads.addLine(to: CGPoint(x: cx - bw/2, y: cy))
        leads.move(to: CGPoint(x: cx + bw/2, y: cy)); leads.addLine(to: CGPoint(x: cx + tw,   y: cy))
        ctx.stroke(leads, with: .color(Color.primary), style: wire)
        var box = Path()
        box.addRect(CGRect(x: cx - bw/2, y: cy - bh/2, width: bw, height: bh))
        ctx.stroke(box, with: .color(Color.primary), lineWidth: 1.8)
    }

    private static func drawBattery(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ tw: CGFloat) {
        let gap: CGFloat = 5; let lh: CGFloat = 22; let sh: CGFloat = 13
        var p = Path()
        p.move(to: CGPoint(x: cx - tw,  y: cy)); p.addLine(to: CGPoint(x: cx - gap, y: cy))
        p.move(to: CGPoint(x: cx + gap, y: cy)); p.addLine(to: CGPoint(x: cx + tw,  y: cy))
        p.move(to: CGPoint(x: cx - gap, y: cy - lh/2)); p.addLine(to: CGPoint(x: cx - gap, y: cy + lh/2))
        p.move(to: CGPoint(x: cx + gap, y: cy - sh/2)); p.addLine(to: CGPoint(x: cx + gap, y: cy + sh/2))
        ctx.stroke(p, with: .color(Color.primary), style: StrokeStyle(lineWidth: 2.0, lineCap: .square))
        ctx.draw(Text("+").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.primary),
                 at: CGPoint(x: cx - gap - 8, y: cy - lh/2))
        ctx.draw(Text("−").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.primary),
                 at: CGPoint(x: cx + gap + 8, y: cy - sh/2))
    }

    private static func drawCapacitor(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ tw: CGFloat) {
        let gap: CGFloat = 5; let ph: CGFloat = 24
        var p = Path()
        p.move(to: CGPoint(x: cx - tw,  y: cy)); p.addLine(to: CGPoint(x: cx - gap, y: cy))
        p.move(to: CGPoint(x: cx + gap, y: cy)); p.addLine(to: CGPoint(x: cx + tw,  y: cy))
        p.move(to: CGPoint(x: cx - gap, y: cy - ph/2)); p.addLine(to: CGPoint(x: cx - gap, y: cy + ph/2))
        p.move(to: CGPoint(x: cx + gap, y: cy - ph/2)); p.addLine(to: CGPoint(x: cx + gap, y: cy + ph/2))
        ctx.stroke(p, with: .color(Color.primary), style: StrokeStyle(lineWidth: 2.0, lineCap: .square))
    }

    private static func drawInductor(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ tw: CGFloat) {
        let r: CGFloat = 6; let n = 4
        let totalW = CGFloat(n) * r * 2; let sx = cx - totalW / 2
        var p = Path()
        p.move(to: CGPoint(x: cx - tw, y: cy)); p.addLine(to: CGPoint(x: sx, y: cy))
        for i in 0..<n {
            p.addArc(center: CGPoint(x: sx + CGFloat(i) * r * 2 + r, y: cy),
                     radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        }
        p.addLine(to: CGPoint(x: cx + tw, y: cy))
        ctx.stroke(p, with: .color(Color.primary), style: wire)
    }

    private static func drawLED(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ tw: CGFloat) {
        let th: CGFloat = 16
        var leads = Path()
        leads.move(to: CGPoint(x: cx - tw,   y: cy)); leads.addLine(to: CGPoint(x: cx - th/2, y: cy))
        leads.move(to: CGPoint(x: cx + th/2, y: cy)); leads.addLine(to: CGPoint(x: cx + tw,   y: cy))
        leads.move(to: CGPoint(x: cx + th/2, y: cy - th/2))
        leads.addLine(to: CGPoint(x: cx + th/2, y: cy + th/2))
        ctx.stroke(leads, with: .color(Color.primary), style: wire)
        var tri = Path()
        tri.move(to: CGPoint(x: cx - th/2, y: cy - th/2))
        tri.addLine(to: CGPoint(x: cx + th/2, y: cy))
        tri.addLine(to: CGPoint(x: cx - th/2, y: cy + th/2))
        tri.closeSubpath()
        ctx.fill(tri, with: .color(.yellow.opacity(0.35)))
        ctx.stroke(tri, with: .color(Color.primary), lineWidth: 1.6)
        var arrows = Path()
        for i in 0..<2 {
            let d = CGFloat(i) * 5
            arrows.move(to: CGPoint(x: cx + th/2 + 4 + d, y: cy - th/2 + d))
            arrows.addLine(to: CGPoint(x: cx + th/2 + 10 + d, y: cy - th/2 - 6 + d))
        }
        ctx.stroke(arrows, with: .color(.yellow.opacity(0.9)),
                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    private static func drawSwitch(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat,
                                   _ tw: CGFloat, closed: Bool) {
        let px: CGFloat = 14; let dr: CGFloat = 2.5
        var p = Path()
        p.move(to: CGPoint(x: cx - tw, y: cy)); p.addLine(to: CGPoint(x: cx - px, y: cy))
        p.move(to: CGPoint(x: cx + px, y: cy)); p.addLine(to: CGPoint(x: cx + tw, y: cy))
        if closed {
            p.move(to: CGPoint(x: cx - px, y: cy)); p.addLine(to: CGPoint(x: cx + px, y: cy))
        } else {
            p.move(to: CGPoint(x: cx - px, y: cy)); p.addLine(to: CGPoint(x: cx + px - 4, y: cy - 14))
        }
        ctx.stroke(p, with: .color(Color.primary), style: wire)
        for dx: CGFloat in [-px, px] {
            ctx.fill(Path(ellipseIn: CGRect(x: cx + dx - dr, y: cy - dr, width: dr * 2, height: dr * 2)),
                     with: .color(Color.primary))
        }
    }

    private static func drawGround(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat) {
        var p = Path()
        p.move(to: CGPoint(x: cx, y: cy - 16)); p.addLine(to: CGPoint(x: cx, y: cy))
        zip([22, 14, 7] as [CGFloat], [0, 6, 12] as [CGFloat]).forEach { (w, dy) in
            p.move(to: CGPoint(x: cx - w/2, y: cy + dy))
            p.addLine(to: CGPoint(x: cx + w/2, y: cy + dy))
        }
        ctx.stroke(p, with: .color(Color.primary), style: StrokeStyle(lineWidth: 1.8, lineCap: .square))
    }

    private static func drawMeter(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat,
                                  _ tw: CGFloat, label: String) {
        let r: CGFloat = 14
        var p = Path()
        p.move(to: CGPoint(x: cx - tw, y: cy)); p.addLine(to: CGPoint(x: cx - r, y: cy))
        p.move(to: CGPoint(x: cx + r,  y: cy)); p.addLine(to: CGPoint(x: cx + tw, y: cy))
        p.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        ctx.stroke(p, with: .color(Color.primary), style: wire)
        ctx.draw(Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.primary),
                 at: CGPoint(x: cx, y: cy))
    }
}
#endif
