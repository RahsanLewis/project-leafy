import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmDeletion = false
    var body: some View {
        List {
            Section("Account") {
                Button("Sign out") { Task { await app.signOut() } }
                Button("Delete account", role: .destructive) { confirmDeletion = true }
            }
            Section("Legal and support") {
                Link("Privacy Policy", destination: app.configuration.privacyURL)
                Link("Terms of Use", destination: app.configuration.termsURL)
                Link("Support", destination: app.configuration.supportURL)
            }
            Section { Text("Leafy provides general wellness estimates and is not a substitute for medical care.").font(.footnote) }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Permanently delete your Leafy account and all plan history?", isPresented: $confirmDeletion, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await app.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        }
        .overlay { if app.saveState == .deleting { ProgressView("Deleting account…").padding().background(.regularMaterial, in: .rect(cornerRadius: 16)) } }
        .alert("Deletion failed", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) { Button("OK") {} } message: { Text(app.errorMessage ?? "") }
    }
}

