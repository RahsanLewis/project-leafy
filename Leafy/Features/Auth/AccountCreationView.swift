import AuthenticationServices
import CryptoKit
import Security
import SwiftUI
import UIKit

struct AccountCreationView: View {
    private enum Field: Hashable { case email, password, confirmation }

    @Environment(AppModel.self) private var app
    @FocusState private var focusedField: Field?
    @State private var rawNonce = ""
    @State private var providerError: String?

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: LeafySpacing.large) {
            VStack(alignment: .leading, spacing: LeafySpacing.small) {
                Text(app.saveState == .awaitingConfirmation ? "Confirm your email" : "Save your plan")
                    .font(LeafyTypography.largeTitle)
                Text(app.saveState == .awaitingConfirmation
                     ? "One last step keeps your nutrition data secure."
                     : "Create an account so your targets, food log, and weight history remain available across devices.")
                    .font(LeafyTypography.body)
                    .foregroundStyle(.secondary)
            }

            if app.saveState == .awaitingConfirmation {
                confirmationContent
            } else {
                agreementRow
                coreDataAgreementRow
                providerButtons
                AuthDivider()
                emailFields

                Text("Use at least 8 characters. A password manager is recommended.")
                    .font(LeafyTypography.caption)
                    .foregroundStyle(.secondary)

                InlineAuthFeedback(
                    isLoading: app.saveState == .creatingAccount || app.saveState == .authenticating || app.saveState == .saving,
                    error: providerError ?? app.errorMessage,
                    status: app.statusMessage
                )

                Button("Create account and save") {
                    focusedField = nil
                    Task {
                        await app.persistPendingOnboarding()
                        await app.createAccount()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!agreementAccepted || app.saveState != .idle)
                .accessibilityIdentifier("createAccountButton")

                Button("Already have an account? Sign in") {
                    focusedField = nil
                    app.presentAuthentication(.accessExistingAccount)
                }
                .font(LeafyTypography.button)
                .frame(maxWidth: .infinity)
                .disabled(app.saveState != .idle)
            }

            Button("Back to plan") { app.draft.step = .results }
                .font(LeafyTypography.button)
                .frame(maxWidth: .infinity)
        }
        .contentShape(.rect)
        .onTapGesture { focusedField = nil }
        .onAppear { Task { await app.persistPendingOnboarding() } }
    }

    private var legalAgreementAccepted: Bool { app.termsAccepted && app.privacyAccepted }
    private var agreementAccepted: Bool { legalAgreementAccepted && app.coreDataAccepted }

    private var agreementRow: some View {
        Button {
            let accepted = !legalAgreementAccepted
            app.termsAccepted = accepted
            app.privacyAccepted = accepted
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(alignment: .top, spacing: LeafySpacing.compact) {
                Image(systemName: legalAgreementAccepted ? "checkmark.square.fill" : "square")
                    .font(LeafyTypography.title3)
                    .foregroundStyle(legalAgreementAccepted ? LeafyTheme.green : .secondary)
                Text("I agree to the [Terms of Use](\(app.configuration.termsURL.absoluteString)) and acknowledge the [Privacy Policy](\(app.configuration.privacyURL.absoluteString)).")
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("accountAgreementCheckbox")
        .accessibilityValue(legalAgreementAccepted ? "Checked" : "Unchecked")
    }

    private var coreDataAgreementRow: some View {
        Button {
            app.coreDataAccepted.toggle()
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(alignment: .top, spacing: LeafySpacing.compact) {
                Image(systemName: app.coreDataAccepted ? "checkmark.square.fill" : "square")
                    .font(LeafyTypography.title3)
                    .foregroundStyle(app.coreDataAccepted ? LeafyTheme.green : .secondary)
                Text("I understand Leafy stores and analyzes my plan, food logs, weight history, and corrections to operate, sync, and personalize the app. [Learn more](\(app.configuration.privacyURL.absoluteString)).")
                    .font(LeafyTypography.footnote)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coreDataAgreementCheckbox")
        .accessibilityValue(app.coreDataAccepted ? "Checked" : "Unchecked")
    }

    private var providerButtons: some View {
        VStack(spacing: LeafySpacing.compact) {
            SignInWithAppleButton(.signUp) { request in
                let nonce = randomNonce()
                rawNonce = nonce
                request.requestedScopes = [.email]
                request.nonce = sha256(nonce)
            } onCompletion: { result in handleApple(result) }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .clipShape(.rect(cornerRadius: LeafyRadius.control))
            .disabled(!agreementAccepted)
            .opacity(agreementAccepted ? 1 : 0.45)

            GoogleAuthenticationButton(purpose: .createAndSave, isEnabled: agreementAccepted)
        }
    }

    private var emailFields: some View {
        @Bindable var app = app
        return VStack(spacing: 0) {
            AuthField(
                label: "Email",
                placeholder: "Email address",
                text: $app.email,
                contentType: .emailAddress,
                keyboardType: .emailAddress,
                isSecure: false,
                submitLabel: .next,
                onSubmit: { focusedField = .password }
            )
            .focused($focusedField, equals: .email)
            AuthField(
                label: "Password",
                placeholder: "Password",
                text: $app.password,
                contentType: .newPassword,
                isSecure: true,
                submitLabel: .next,
                onSubmit: { focusedField = .confirmation }
            )
            .focused($focusedField, equals: .password)
            AuthField(
                label: "Confirm password",
                placeholder: "Confirm password",
                text: $app.passwordConfirmation,
                contentType: .newPassword,
                isSecure: true,
                submitLabel: .done,
                onSubmit: { focusedField = nil }
            )
            .focused($focusedField, equals: .confirmation)
        }
    }

    private var confirmationContent: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.large) {
            Label(app.email, systemImage: "envelope.badge")
                .font(LeafyTypography.headline)
                .foregroundStyle(LeafyTheme.green)
            Text("Open the secure confirmation link in your email, then return to Leafy to finish saving your plan.")
                .font(LeafyTypography.body)
                .foregroundStyle(.secondary)

            InlineAuthFeedback(
                isLoading: app.saveState == .resendingConfirmation,
                error: app.errorMessage,
                status: app.statusMessage
            )

            Button("I’ve confirmed my email") { Task { await app.finishConfirmedAccount() } }
                .buttonStyle(PrimaryButtonStyle())
            Button(app.saveState == .resendingConfirmation ? "Sending…" : "Resend confirmation email") {
                Task { await app.resendAccountConfirmation() }
            }
            .font(LeafyTypography.button)
            .frame(maxWidth: .infinity)
            .disabled(app.saveState == .resendingConfirmation)
            Button("Use a different email") {
                app.saveState = .idle
                app.errorMessage = nil
                app.statusMessage = nil
            }
            .font(LeafyTypography.button)
            .frame(maxWidth: .infinity)
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, any Error>) {
        guard agreementAccepted else { return }
        guard case let .success(authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken,
              let token = String(data: data, encoding: .utf8), !rawNonce.isEmpty else {
            if case let .failure(error) = result,
               (error as? ASAuthorizationError)?.code == .canceled { return }
            providerError = "Apple couldn’t complete account creation. Please try again."
            return
        }
        Task {
            await app.persistPendingOnboarding()
            await app.saveAfterApple(identityToken: token, nonce: rawNonce)
        }
    }

    private func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in
            var byte: UInt8 = 0
            precondition(SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess)
            return characters[Int(byte) % characters.count]
        })
    }
}
