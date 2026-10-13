//
//  GradeClassDetailView.swift
//  Tolerance
//
//  One class's grade breakdown: a donut chart of its weighted categories
//  with the overall grade in the center, then each category as an
//  expandable card where assignments can be added and scored.
//

import SwiftUI
import SwiftData
import Charts

struct GradeClassDetailView: View {
    @Bindable var gradeClass: GradeClass
    @Environment(\.modelContext) private var modelContext
    var onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                GradePieChart(
                    categories: gradeClass.orderedCategories,
                    overallGrade: gradeClass.overallGrade
                )
                .frame(height: 240)
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Categories")
                        .font(.headline)

                    ForEach(Array(gradeClass.orderedCategories.enumerated()), id: \.element.persistentModelID) { index, category in
                        GradeCategoryCard(
                            category: category,
                            color: GradeScale.color(forCategoryAt: index),
                            onDelete: { deleteCategory(category) },
                            onAddAssignment: { addAssignment(to: category) },
                            onDeleteAssignment: { deleteAssignment($0) }
                        )
                    }

                    Button(action: addCategory) {
                        Label("Add Category", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .navigationTitle(gradeClass.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) {
                    Label("Classes", systemImage: "chevron.left")
                }
            }
        }
    }

    private func addCategory() {
        let category = GradeCategory(name: "New Category", weightPercent: 0, orderIndex: gradeClass.categories.count)
        category.gradeClass = gradeClass
        gradeClass.categories.append(category)
        modelContext.insert(category)
    }

    private func deleteCategory(_ category: GradeCategory) {
        modelContext.delete(category)
    }

    private func addAssignment(to category: GradeCategory) {
        let assignment = GradeAssignment(name: "New Assignment", pointsEarned: 0, pointsPossible: 100, orderIndex: category.assignments.count)
        assignment.category = category
        category.assignments.append(assignment)
        modelContext.insert(assignment)
    }

    private func deleteAssignment(_ assignment: GradeAssignment) {
        modelContext.delete(assignment)
    }
}

// MARK: - Pie chart

private struct GradePieChart: View {
    let categories: [GradeCategory]
    let overallGrade: Double?

    private var totalWeight: Double {
        categories.reduce(0) { $0 + $1.weightPercent }
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                if categories.isEmpty || totalWeight <= 0 {
                    Circle()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 28)
                    Text("Add a category\nto get started")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else {
                    Chart {
                        ForEach(Array(categories.enumerated()), id: \.element.persistentModelID) { index, category in
                            SectorMark(
                                angle: .value("Weight", category.weightPercent),
                                innerRadius: .ratio(0.62),
                                angularInset: 1.5
                            )
                            .foregroundStyle(GradeScale.color(forCategoryAt: index))
                            .cornerRadius(4)
                        }
                    }
                    .chartLegend(.hidden)

                    centerLabel
                }
            }
            .frame(height: 170)

            legend
        }
    }

    @ViewBuilder
    private var centerLabel: some View {
        VStack(spacing: 2) {
            if let overallGrade {
                Text(String(format: "%.1f%%", overallGrade))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(GradeScale.color(for: overallGrade))
                Text(GradeScale.letter(for: overallGrade))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("No grades yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var legend: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(categories.enumerated()), id: \.element.persistentModelID) { index, category in
                HStack(spacing: 6) {
                    Circle()
                        .fill(GradeScale.color(forCategoryAt: index))
                        .frame(width: 8, height: 8)
                    Text(category.name)
                        .font(.caption)
                    Text(String(format: "%.0f%%", category.weightPercent))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Minimal wrapping HStack for the chart legend, since legend items vary
/// in width and a plain HStack would overflow off-screen with several
/// categories.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Category card

private struct GradeCategoryCard: View {
    @Bindable var category: GradeCategory
    let color: Color
    var onDelete: () -> Void
    var onAddAssignment: () -> Void
    var onDeleteAssignment: (GradeAssignment) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle().fill(color).frame(width: 10, height: 10)

                TextField("Category name", text: $category.name)
                    .textFieldStyle(.plain)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                HStack(spacing: 2) {
                    TextField("0", value: $category.weightPercent, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 32)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("%")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                Group {
                    if let average = category.average {
                        Text(String(format: "%.0f%%", average))
                            .foregroundStyle(color)
                    } else {
                        Text("--")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption.weight(.semibold))
                .frame(width: 40, alignment: .trailing)

                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            if isExpanded {
                Divider()
                VStack(spacing: 8) {
                    if category.orderedAssignments.isEmpty {
                        Text("No assignments yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(category.orderedAssignments) { assignment in
                        GradeAssignmentRow(assignment: assignment) {
                            onDeleteAssignment(assignment)
                        }
                    }
                    Button(action: onAddAssignment) {
                        Label("Add Assignment", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(12)
            }
        }
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.12)))
    }
}

// MARK: - Assignment row

private struct GradeAssignmentRow: View {
    @Bindable var assignment: GradeAssignment
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Assignment", text: $assignment.name)
                .textFieldStyle(.plain)
                .font(.subheadline)

            Spacer()

            TextField("0", value: $assignment.pointsEarned, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 40)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Text("/")
                .foregroundStyle(.secondary)
            TextField("100", value: $assignment.pointsPossible, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 40)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif

            Group {
                if let percent = assignment.percent {
                    Text(String(format: "%.0f%%", percent))
                } else {
                    Text("--")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 40, alignment: .trailing)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    let gradeClass = GradeClass(name: "AP Physics 1")
    return NavigationStack {
        GradeClassDetailView(gradeClass: gradeClass, onBack: {})
    }
    .modelContainer(for: [GradeClass.self, GradeCategory.self, GradeAssignment.self], inMemory: true)
}
