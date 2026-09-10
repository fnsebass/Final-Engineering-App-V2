//
//  TutorRecognitionSettingsView.swift
//  Tolerance
//
//  Handwriting-to-LaTeX conversion, diagram auto-smoothing, and structural
//  symbol recognition. The app currently reads handwriting via Vision's text
//  recognizer (EquationOCR) and strips LaTeX rather than producing it
//  (AITextSanitizer), so these are saved preferences for future recognition
//  behavior rather than live switches.
//

import SwiftUI

struct TutorRecognitionSettingsView: View {
    @AppStorage("settings.tutor.liveReviewEnabled") private var liveReviewEnabled = true
    @AppStorage("settings.tutor.liveLatex") private var liveLatex = false
    @AppStorage("settings.tutor.diagramAutoSmoothing") private var diagramAutoSmoothing = true
    @AppStorage("settings.tutor.symbolRecognition") private var symbolRecognition = true

    var body: some View {
        Form {
            Section {
                Toggle("Real-Time Equation Checking", isOn: $liveReviewEnabled)
            } footer: {
                Text("About a second after you pause writing, the last equation you wrote is checked automatically and gets a small check or X mark. Turn this off to only check manually via the double-tap menu.")
                    .font(.caption)
            }

            Section {
                Toggle("Real-Time Handwriting → LaTeX", isOn: $liveLatex)
            } footer: {
                UnwiredNote("Handwriting is currently read as plain text (Vision OCR); it isn't converted to LaTeX yet.")
            }

            Section {
                Toggle("Diagram Auto-Smoothing", isOn: $diagramAutoSmoothing)
            } footer: {
                UnwiredNote("Free-body, circuit, truss, and beam diagrams don't auto-smooth strokes yet.")
            }

            Section {
                Toggle("Chemical & Math Symbol Recognition", isOn: $symbolRecognition)
            } footer: {
                UnwiredNote("The AI review already reads chemical/math context from a photo, but there's no dedicated structural symbol recognizer this toggle controls yet.")
            }
        }
        .navigationTitle("Tutor & Recognition")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack { TutorRecognitionSettingsView() }
}
