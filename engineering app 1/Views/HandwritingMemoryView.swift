//
//  HandwritingMemoryView.swift
//  Tolerance
//
//  Shows all learned handwriting-to-character associations.
//  Each row can be deleted individually; bulk delete is intentionally absent.
//

import SwiftUI
import SwiftData

struct HandwritingMemoryView: View {
    @Query(sort: \HandwritingCorrection.useCount, order: .reverse)
    private var corrections: [HandwritingCorrection]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            if corrections.isEmpty {
                emptyState
            } else {
                Section {
                    ForEach(corrections) { correction in
                        correctionRow(correction)
                    }
                } header: {
                    Text("Tap the trash icon to remove a single entry.")
                        .font(.caption)
                        .textCase(nil)
                }
            }
        }
        .navigationTitle("Handwriting Memory")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Row

    private func correctionRow(_ c: HandwritingCorrection) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                // OCR fragment → corrected
                HStack(spacing: 8) {
                    Text(c.ocrFragment)
                        .font(.body.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.orange)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(c.correctedFragment)
                        .font(.body.monospaced().weight(.semibold))
                }

                if !c.exampleContext.isEmpty {
                    Text("In: \"\(c.exampleContext)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Image(systemName: "repeat")
                        .font(.caption2)
                    Text("Applied \(c.useCount) time\(c.useCount == 1 ? "" : "s")")
                    Text("·")
                    Text(c.dateAdded, format: .relative(presentation: .named))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            // Individual delete — intentionally one-at-a-time
            Button(role: .destructive) {
                withAnimation { modelContext.delete(c) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 34, height: 34)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Handwriting Memory", systemImage: "hand.draw")
        } description: {
            Text("""
                When the AI is uncertain about a character while graphing or \
                solving, it asks you to clarify. Your answers are saved here \
                and applied automatically to future scans of your handwriting.
                """)
        }
    }
}

#Preview {
    NavigationStack {
        HandwritingMemoryView()
    }
    .modelContainer(for: HandwritingCorrection.self, inMemory: true)
}
