//
//  AIPracticeSetupView.swift
//  Tolerance
//
//  AI Practice mode: a peer to Home and Library in the sidebar. Lists
//  previously generated practice notepads and offers a form to generate a
//  new one (class + unit + question count). Generated notepads are real
//  Notepad/Page objects — reusing the full existing canvas/editor stack —
//  just flagged `isAIPractice` so Home's grid and the loose-notes list
//  filter them out; this screen is the only place they're browsable from.
//

import SwiftUI
import SwiftData

struct AIPracticeHomeView: View {
    let practiceSets: [Notepad]
    let onOpen: (Notepad) -> Void

    @State private var showSetup = false

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 165), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("AI Practice")
                    .font(.system(size: 30, weight: .bold, design: .serif))

                Button {
                    showSetup = true
                } label: {
                    Label("New Practice Set", systemImage: "wand.and.stars")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)

                if practiceSets.isEmpty {
                    ContentUnavailableView {
                        Label("No Practice Sets Yet", systemImage: "wand.and.stars")
                    } description: {
                        Text("Generate a set of practice questions for a class and unit, then write your answers right on the page.")
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(practiceSets) { note in
                            Button { onOpen(note) } label: {
                                NotepadCard(notepad: note, showDate: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("AI Practice")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showSetup) {
            AIPracticeSetupView { notepad in
                showSetup = false
                onOpen(notepad)
            }
        }
    }
}

// MARK: - Setup form

struct AIPracticeSetupView: View {
    var onGenerated: (Notepad) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var className = ""
    @State private var unitName = ""
    @State private var questionCount = 10
    @State private var isGenerating = false
    @State private var errorMessage: String?

    private var isAIAvailable: Bool { AIPracticeGenerator.isAIAvailable }

    private var canGenerate: Bool {
        !className.trimmingCharacters(in: .whitespaces).isEmpty &&
        !unitName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isGenerating
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Class") {
                    TextField("e.g. AP Physics 1", text: $className)
                        .disabled(isGenerating)
                }
                Section("Unit") {
                    TextField("e.g. Kinematics", text: $unitName)
                        .disabled(isGenerating)
                }
                Section("Questions") {
                    Stepper("\(questionCount) questions", value: $questionCount, in: 1...25)
                        .disabled(isGenerating)
                }

                if !isAIAvailable {
                    Section {
                        Label("On-device AI is unavailable on this device.", systemImage: "exclamationmark.icloud")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await generate() }
                    } label: {
                        HStack {
                            Spacer()
                            if isGenerating {
                                ProgressView()
                            } else {
                                Label("Generate", systemImage: "sparkles")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .disabled(!canGenerate || !isAIAvailable)
                }
            }
            .navigationTitle("New Practice Set")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isGenerating)
                }
            }
        }
        .interactiveDismissDisabled(isGenerating)
    }

    private func generate() async {
        isGenerating = true
        errorMessage = nil
        do {
            let notepad = try await AIPracticeGenerator.generate(
                className: className.trimmingCharacters(in: .whitespaces),
                unitName: unitName.trimmingCharacters(in: .whitespaces),
                questionCount: questionCount,
                in: modelContext
            )
            isGenerating = false
            onGenerated(notepad)
        } catch {
            isGenerating = false
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { AIPracticeSetupView { _ in } }
}

// MARK: - Grading results

/// Shown after tapping Submit in the notepad's palette — one row per
/// question with the Gemini-graded verdict and brief feedback.
struct AIPracticeGradingResultsView: View {
    @Bindable var notepad: Notepad
    @Environment(\.dismiss) private var dismiss

    private var questions: [AIPracticeQuestion] { notepad.orderedAIPracticeQuestions }
    private var gradedCount: Int { questions.filter { $0.isCorrect != nil }.count }
    private var correctCount: Int { questions.filter { $0.isCorrect == true }.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Score")
                        Spacer()
                        Text("\(correctCount) / \(gradedCount)")
                            .font(.headline)
                    }
                }

                ForEach(questions) { question in
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(question.text)
                                .font(.subheadline.weight(.medium))

                            if let feedback = question.gradeFeedback {
                                Label(
                                    feedback,
                                    systemImage: question.isCorrect == true
                                        ? "checkmark.circle.fill" : "xmark.circle.fill"
                                )
                                .font(.caption)
                                .foregroundStyle(question.isCorrect == true ? .green : .red)
                            } else {
                                Text("Not graded.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Grading Results")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
