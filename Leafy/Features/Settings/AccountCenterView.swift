import SwiftUI

struct AccountCenterView: View {
    private enum Confirmation: String, Identifiable {
        case signOutAll, delete
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var app
    @Environment(AppLockCoordinator.self) private var appLock
    @State private var credentialKind: CredentialChangeView.Kind?
    @State private var confirmation: Confirmation?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: LeafySpacing.small) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(LeafyTypography.icon(46, relativeTo: .largeTitle))
                        .foregroundStyle(LeafyTheme.green)
                    Text(app.account?.email ?? "Leafy account")
                        .font(LeafyTypography.title2)
                    Text(accountSummary)
                        .font(LeafyTypography.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, LeafySpacing.medium)
            }
            .leafyBorderlessRows(separators: false)

            Section("Security") {
                Toggle("Require \(appLock.biometricName)", isOn: Binding(
                    get: { appLock.isEnabled },
                    set: { enabled in Task { _ = enabled ? await appLock.enable() : await appLock.disable() } }
                ))

                Menu {
                    Button("Change email") { credentialKind = .email }
                    Button("Change password") { credentialKind = .password }
                } label: {
                    settingsMenuLabel("Manage credentials", symbol: "key")
                }
            }
            .leafyBorderlessRows()

            Section("Account access") {
                Menu {
                    Button("Sign out of all devices", role: .destructive) { confirmation = .signOutAll }
                } label: {
                    settingsMenuLabel("Manage sessions", symbol: "rectangle.portrait.and.arrow.right")
                }

                Menu {
                    Button("Delete account", role: .destructive) { confirmation = .delete }
                } label: {
                    settingsMenuLabel("Manage account", symbol: "person.crop.circle.badge.minus")
                }
            }
            .leafyBorderlessRows()

            Section {
                Text("Deleting your account permanently removes your profile, plans, food logs, weight history, and product contributions.")
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, LeafySpacing.small)
            }
            .leafyBorderlessRows(separators: false)
        }
        .leafyBorderlessList()
        .navigationTitle("Account & Security")
        .navigationBarTitleDisplayMode(.inline)
        .task { await app.refreshAccount() }
        .sheet(item: $credentialKind) { CredentialChangeView(kind: $0) }
        .sheet(item: $confirmation) { choice in
            LeafyConfirmationSheet(
                title: confirmationTitle(for: choice),
                message: confirmationMessage(for: choice),
                confirmTitle: choice == .signOutAll ? "Sign out everywhere" : "Delete account",
                isDestructive: true,
                confirmIdentifier: choice == .signOutAll ? "confirmSignOutEverywhereButton" : "confirmDeleteAccountButton",
                sheetIdentifier: choice == .signOutAll ? "signOutEverywhereConfirmationSheet" : "deleteAccountConfirmationSheet"
            ) {
                if choice == .signOutAll {
                    Task { await app.signOutEverywhere() }
                } else {
                    Task { await app.deleteAccount() }
                }
            }
        }
    }

    private var accountSummary: String {
        let status = app.account?.emailConfirmed == true ? "Verified" : "Verification pending"
        let methods = app.account?.identities.map(\.displayName).joined(separator: ", ") ?? "Email"
        return "\(status) · \(methods)"
    }

    private func confirmationTitle(for confirmation: Confirmation) -> String {
        switch confirmation {
        case .signOutAll: "Sign out of every device?"
        case .delete: "Permanently delete your Leafy account?"
        }
    }

    private func confirmationMessage(for confirmation: Confirmation) -> String {
        switch confirmation {
        case .signOutAll: "Every device using this account will need to sign in again."
        case .delete: "This permanently removes your profile, plans, food logs, weight history, and product contributions."
        }
    }

    private func settingsMenuLabel(_ title: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

struct CredentialChangeView: View {
    enum Kind: String, Identifiable {
        case email, password
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let kind: Kind
    @State private var value = ""
    @State private var currentPassword = ""
    @FocusState private var focusedField: Field?
    private enum Field { case value, password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LeafySpacing.xLarge) {
                    VStack(alignment: .leading, spacing: LeafySpacing.small) {
                        Text(title)
                            .font(LeafyTypography.title)
                        Text("Confirm your current password before changing sensitive account information.")
                            .font(LeafyTypography.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 0) {
                        Group {
                            if kind == .email {
                                TextField("New email address", text: $value)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                            } else {
                                SecureField("New password", text: $value)
                                    .textContentType(.newPassword)
                            }
                        }
                        .focused($focusedField, equals: .value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.vertical, LeafySpacing.medium)

                        Divider()

                        SecureField("Current password", text: $currentPassword)
                            .textContentType(.password)
                            .focused($focusedField, equals: .password)
                            .padding(.vertical, LeafySpacing.medium)
                    }

                    if let error = app.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(LeafyTypography.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(LeafyTheme.pageInset)
            }
            .background(LeafyTheme.canvas)
            .navigationTitle(kind == .email ? "Email" : "Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button(app.saveState == .saving ? "Saving…" : "Save change") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(value.isEmpty || currentPassword.isEmpty || app.saveState == .saving)
                    .leafyDetachedBottomControl()
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var title: String { kind == .email ? "Change your email" : "Choose a new password" }

    private func save() {
        Task {
            let success = kind == .email
                ? await app.changeEmail(to: value, currentPassword: currentPassword)
                : await app.changePassword(to: value, currentPassword: currentPassword)
            if success { dismiss() }
        }
    }
}
