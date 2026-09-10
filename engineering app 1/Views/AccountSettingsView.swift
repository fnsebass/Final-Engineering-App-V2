//
//  AccountSettingsView.swift
//  Tolerance
//
//  Profile details and device list. The app has no cloud account system —
//  everything lives in an on-device SwiftData store — so this screen stores
//  a local display name/email only and lists just the current device.
//

import SwiftUI

struct AccountSettingsView: View {
    @AppStorage("settings.account.displayName") private var displayName = ""
    @AppStorage("settings.account.email") private var email = ""

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $displayName)
                TextField("Email", text: $email)
                    #if os(iOS)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            } header: {
                Text("Profile")
            } footer: {
                UnwiredNote("There's no cloud account system yet — this is stored locally and isn't used to sign in anywhere.")
            }

            Section {
                Label("This iPad (Current Device)", systemImage: "ipad")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Active Devices")
            } footer: {
                Text("Multi-device management requires the Sync feature to be connected to a cloud account, which isn't implemented yet.")
                    .font(.caption)
            }
        }
        .navigationTitle("Account")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack { AccountSettingsView() }
}
