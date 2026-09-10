//
//  PenStylusSettingsView.swift
//  Tolerance
//
//  Pressure/tilt behavior, palm rejection, and line smoothing. Squeeze/
//  double-tap button mapping lives in Settings → Writing → Pen Buttons,
//  which is wired to the real UIPencilInteractionDelegate in PencilCanvasView.
//

import SwiftUI

enum PressureCurve: String, CaseIterable, Identifiable {
    case linear, soft, firm
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct PenStylusSettingsView: View {
    @AppStorage("settings.pen.pressureCurve") private var pressureCurveRaw = PressureCurve.linear.rawValue
    @AppStorage("settings.pen.tiltDetection") private var tiltDetection = true
    @AppStorage("settings.pen.palmRejection") private var palmRejection = 0.5
    @AppStorage("settings.pen.lineSmoothing") private var lineSmoothing = true

    var body: some View {
        Form {
            Section {
                Picker("Pressure Curve", selection: $pressureCurveRaw) {
                    ForEach(PressureCurve.allCases) { curve in
                        Text(curve.displayName).tag(curve.rawValue)
                    }
                }
            } header: {
                Text("Pressure Sensitivity")
            } footer: {
                UnwiredNote("Stroke width already responds to Apple Pencil pressure; this curve doesn't remap it yet.")
            }

            Section {
                Toggle("Tilt Detection", isOn: $tiltDetection)
            } footer: {
                UnwiredNote("Not yet used for shading or nib-angle effects.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Slider(value: $palmRejection, in: 0...1)
                    Text(palmRejection < 0.34 ? "Low" : palmRejection < 0.67 ? "Medium" : "High")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Palm Rejection Sensitivity")
            } footer: {
                UnwiredNote("The canvas already ignores finger touches while drawing (Apple Pencil only); this slider doesn't change that threshold yet.")
            }

            Section {
                Toggle("Line Smoothing", isOn: $lineSmoothing)
            } footer: {
                UnwiredNote("PencilKit already applies its own default stroke smoothing; this toggle doesn't add an extra algorithm yet.")
            }
        }
        .navigationTitle("Pen & Stylus")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack { PenStylusSettingsView() }
}
