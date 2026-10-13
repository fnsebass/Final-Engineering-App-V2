//
//  GradeCalculatorView.swift
//  Tolerance
//
//  The "Grade Calculator" destination, reached from Home's sidebar like
//  Library or AI Practice. Shows a grid of classes; tapping one opens its
//  weighted-category breakdown (GradeClassDetailView) in place, with a
//  back button returning here — self-contained, so it needs no changes to
//  HomeView's own folder/notepad selection logic.
//

import SwiftUI
import SwiftData

struct GradeCalculatorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GradeClass.createdDate, order: .reverse) private var classes: [GradeClass]

    @State private var selectedClass: GradeClass?
    @State private var showNewClassAlert = false
    @State private var newClassName = ""
    @State private var renameTarget: GradeClass?
    @State private var renameText = ""
    @State private var showRenameAlert = false

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 20)]

    var body: some View {
        Group {
            if let selectedClass, classes.contains(where: { $0.persistentModelID == selectedClass.persistentModelID }) {
                GradeClassDetailView(gradeClass: selectedClass, onBack: { self.selectedClass = nil })
                    .id(selectedClass.persistentModelID)
            } else {
                classGrid
            }
        }
        .alert("New Class", isPresented: $showNewClassAlert) {
            TextField("Class name", text: $newClassName)
            Button("Cancel", role: .cancel) { newClassName = "" }
            Button("Create") { createClass() }
        }
        .alert("Rename Class", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") { commitRename() }
        }
    }

    private var classGrid: some View {
        ScrollView {
            if classes.isEmpty {
                ContentUnavailableView {
                    Label("No Classes Yet", systemImage: "chart.pie")
                } description: {
                    Text("Add a class to start tracking its grade.")
                } actions: {
                    Button("Add Class") {
                        newClassName = ""
                        showNewClassAlert = true
                    }
                }
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(classes) { gradeClass in
                        Button { selectedClass = gradeClass } label: {
                            GradeClassCard(gradeClass: gradeClass)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { beginRename(gradeClass) } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) { deleteClass(gradeClass) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("Grade Calculator")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newClassName = ""
                    showNewClassAlert = true
                } label: {
                    Label("Add Class", systemImage: "plus")
                }
            }
        }
    }

    private func createClass() {
        let trimmed = newClassName.trimmingCharacters(in: .whitespacesAndNewlines)
        let gradeClass = GradeClass(name: trimmed.isEmpty ? "New Class" : trimmed)
        modelContext.insert(gradeClass)
        newClassName = ""
    }

    private func beginRename(_ gradeClass: GradeClass) {
        renameTarget = gradeClass
        renameText = gradeClass.name
        showRenameAlert = true
    }

    private func commitRename() {
        guard let renameTarget else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { renameTarget.name = trimmed }
        self.renameTarget = nil
    }

    private func deleteClass(_ gradeClass: GradeClass) {
        if selectedClass?.persistentModelID == gradeClass.persistentModelID {
            selectedClass = nil
        }
        modelContext.delete(gradeClass)
    }
}

// MARK: - Class card

private struct GradeClassCard: View {
    let gradeClass: GradeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(gradeClass.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }

            Text("\(gradeClass.categories.count) \(gradeClass.categories.count == 1 ? "category" : "categories")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            HStack {
                Spacer()
                if let grade = gradeClass.overallGrade {
                    Text(String(format: "%.1f%%", grade))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(GradeScale.color(for: grade))
                } else {
                    Text("--")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(height: 130, alignment: .top)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.15)))
    }
}

// MARK: - Shared grade helpers

enum GradeScale {
    /// A muted traffic-light color for a percentage grade, consistent
    /// everywhere a grade is shown (class cards, pie chart center, etc.).
    static func color(for percent: Double) -> Color {
        switch percent {
        case 90...: return hexColor("#588C88")
        case 80..<90: return hexColor("#7A8F6E")
        case 70..<80: return hexColor("#C7A045")
        case 60..<70: return hexColor("#B9702F")
        default: return hexColor("#B76F4B")
        }
    }

    static func letter(for percent: Double) -> String {
        switch percent {
        case 93...: return "A"
        case 90..<93: return "A-"
        case 87..<90: return "B+"
        case 83..<87: return "B"
        case 80..<83: return "B-"
        case 77..<80: return "C+"
        case 73..<77: return "C"
        case 70..<73: return "C-"
        case 67..<70: return "D+"
        case 63..<67: return "D"
        case 60..<63: return "D-"
        default: return "F"
        }
    }

    /// Cycled by index to color each category consistently across the pie
    /// chart, its legend, and the category cards below it.
    static let categoryPalette: [Color] = [
        hexColor("#5B7C99"), hexColor("#B76F4B"), hexColor("#7A8F6E"),
        hexColor("#8B6A8E"), hexColor("#C7A045"), hexColor("#588C88"),
        hexColor("#B98787"), hexColor("#8B8F5A")
    ]

    static func color(forCategoryAt index: Int) -> Color {
        categoryPalette[index % categoryPalette.count]
    }

    /// Self-contained "#RRGGBB" parser, named to avoid colliding with the
    /// Color(hex:) initializer already declared in FBDEditorView.swift.
    fileprivate static func hexColor(_ hex: String) -> Color {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: string).scanHexInt64(&value)
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

#Preview {
    NavigationStack { GradeCalculatorView() }
        .modelContainer(for: [GradeClass.self, GradeCategory.self, GradeAssignment.self], inMemory: true)
}
