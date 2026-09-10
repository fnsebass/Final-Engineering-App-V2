//
//  SupportLegalSettingsView.swift
//  Tolerance
//
//  Contact support, documentation, privacy policy, terms of service, and
//  license information. Support and the privacy policy point at the real
//  contact email / README content added in the "support/privacy links"
//  commit; Terms of Service and License point at the same repo since
//  dedicated documents don't exist yet.
//

import SwiftUI

struct SupportLegalSettingsView: View {
    private let repoURL = URL(string: "https://github.com/fnsebass/Final-Engineering-App-V2")!
    private let supportEmailURL = URL(string: "mailto:frienlyguy200@gmail.com")!

    var body: some View {
        Form {
            Section {
                Link(destination: supportEmailURL) {
                    Label("Contact Support", systemImage: "questionmark.circle")
                }
                Link(destination: repoURL) {
                    Label("Documentation", systemImage: "book")
                }
            }

            Section {
                Link(destination: repoURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                Link(destination: repoURL) {
                    Label("Terms of Service", systemImage: "doc.text")
                }
                Link(destination: repoURL) {
                    Label("Software Licenses", systemImage: "text.book.closed")
                }
            } footer: {
                Text("Terms of Service and Software Licenses currently link to the project repository; standalone documents haven't been published yet.")
                    .font(.caption)
            }
        }
        .navigationTitle("Support & Legal")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack { SupportLegalSettingsView() }
}
