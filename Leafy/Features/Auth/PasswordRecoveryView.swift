import SwiftUI

struct PasswordRecoveryView: View {
    enum Mode { case request, choosePassword }
    private enum Field: Hashable { case email, password, confirmation }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    let initialMode: Mode
    var embedsNavigation = true
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var sent = false

    var body: some View {
        Group {
            if embedsNavigation {
                NavigationStack { recoveryContent }
            } else {
                recoveryContent
            }
        }
    }

    private var recoveryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LeafySpacing.large) {
                VStack(alignment: .leading, spacing: LeafySpacing.small) {
                    Text(initialMode == .request ? "Reset your password" : "Choose a new password")
                        .font(LeafyTypography.largeTitle)
                    Text(initialMode == .request
                         ? "Enter your account email and we’ll send a secure reset link."
                         : "Use at least 8 characters. You’ll sign in again after updating it.")
                        .font(LeafyTypography.body)
                        .foregroundStyle(.secondary)
                }

                if initialMode == .request {
                    requestContent
                } else {
                    passwordContent
                }

                InlineAuthFeedback(
                    isLoading: false,
                    error: app.errorMessage,
                    status: app.statusMessage
                )
            }
            .padding(LeafyTheme.pageInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LeafyTheme.canvas)
        .contentShape(.rect)
        .onTapGesture { focusedField = nil }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if embedsNavigation {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var requestContent: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.large) {
            AuthField(
                label: "Email",
                placeholder: "Email address",
                text: $email,
                contentType: .emailAddress,
                keyboardType: .emailAddress,
                isSecure: false,
                submitLabel: .go,
                onSubmit: sendReset
            )
            .focused($focusedField, equals: .email)

            Button(sent ? "Reset link sent" : "Send reset link", action: sendReset)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(sent || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Text(sent
                 ? "Check your email for the secure link. You can close this screen while you wait."
                 : "For privacy, Leafy shows the same result whether or not that email has an account.")
                .font(LeafyTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var passwordContent: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.large) {
            VStack(spacing: 0) {
                AuthField(
                    label: "New password",
                    placeholder: "New password",
                    text: $password,
                    contentType: .newPassword,
                    isSecure: true,
                    submitLabel: .next,
                    onSubmit: { focusedField = .confirmation }
                )
                .focused($focusedField, equals: .password)
                AuthField(
                    label: "Confirm password",
                    placeholder: "Confirm password",
                    text: $confirmation,
                    contentType: .newPassword,
                    isSecure: true,
                    submitLabel: .done,
                    onSubmit: updatePassword
                )
                .focused($focusedField, equals: .confirmation)
            }

            Button("Update password", action: updatePassword)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(password.count < 8 || confirmation.isEmpty)
        }
    }

    private func sendReset() {
        focusedField = nil
        Task { sent = await app.requestPasswordReset(email: email) }
    }

    private func updatePassword() {
        focusedField = nil
        guard password == confirmation else {
            app.errorMessage = "Passwords do not match."
            return
        }
        Task { if await app.completePasswordReset(password) { dismiss() } }
    }
}
