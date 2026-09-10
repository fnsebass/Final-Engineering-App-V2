//
//  OnboardingView.swift
//  Tolerance
//
//  Minimal first-run tutorial shown once from HomeView, and re-shown on
//  demand from Settings → General → Reset Onboarding Tutorial.
//

import SwiftUI

private struct OnboardingPage: Identifiable {
    let id = Int.random(in: 0...Int.max)
    let icon: String
    let title: String
    let body: String
}

private let onboardingPages: [OnboardingPage] = [
    OnboardingPage(
        icon: "pencil.tip",
        title: "Write With Apple Pencil",
        body: "Draw equations, diagrams, and notes directly on engineering-grid, dot, or lined paper. Squeeze the pencil to erase, double-tap to toggle it."
    ),
    OnboardingPage(
        icon: "sparkles",
        title: "Ask AI to Check Your Work",
        body: "Long-press anything you've written to check it, get a step-by-step explanation, or analyze a chemistry problem — on-device, no internet required."
    ),
    OnboardingPage(
        icon: "slider.horizontal.3",
        title: "Make It Yours",
        body: "Open Settings from the home screen to change themes, paper defaults, pen behavior, and the on-device tutor's style."
    )
]

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var pageIndex = 0

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $pageIndex) {
                ForEach(Array(onboardingPages.enumerated()), id: \.offset) { index, page in
                    VStack(spacing: 18) {
                        Image(systemName: page.icon)
                            .font(.system(size: 56, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        Text(page.title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text(page.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif

            Button(pageIndex == onboardingPages.count - 1 ? "Get Started" : "Next") {
                if pageIndex == onboardingPages.count - 1 {
                    onFinish()
                } else {
                    withAnimation { pageIndex += 1 }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
        .frame(minWidth: 420, minHeight: 460)
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
