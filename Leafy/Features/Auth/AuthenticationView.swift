import AuthenticationServices
import CryptoKit
import Security
import SwiftUI
import UIKit

struct AuthenticationView: View {
    private enum Field: Hashable { case email, password }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var rawNonce = ""
    @State private var appleErrorMessage: String?

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LeafySpacing.large) {
                    VStack(alignment: .leading, spacing: LeafySpacing.small) {
                        Text("Welcome back").font(LeafyTypography.largeTitle)
                        Text("Sign in to access your saved nutrition plan, food log, and weight history.")
                            .font(LeafyTypography.body)
                            .foregroundStyle(.secondary)
                    }

                    providerButtons
                    AuthDivider()

                    VStack(spacing: 0) {
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
                            contentType: .password,
                            isSecure: true,
                            submitLabel: .go,
                            onSubmit: signIn
                        )
                        .focused($focusedField, equals: .password)
                    }

                    NavigationLink("Forgot password?") {
                        PasswordRecoveryView(initialMode: .request, embedsNavigation: false)
                    }
                    .font(LeafyTypography.footnote)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    InlineAuthFeedback(
                        isLoading: app.saveState == .authenticating,
                        error: appleErrorMessage ?? app.errorMessage,
                        status: app.statusMessage
                    )

                    Button("Sign in", action: signIn)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(app.saveState != .idle)
                        .accessibilityIdentifier("signInButton")

                    Text("New to Leafy? Close this sheet and continue to preview your personalized plan before creating an account.")
                        .font(LeafyTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(LeafyTheme.pageInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(LeafyTheme.canvas)
            .contentShape(.rect)
            .onTapGesture { focusedField = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        app.errorMessage = nil
                        app.statusMessage = nil
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(app.saveState == .authenticating)
        .onAppear {
            app.errorMessage = nil
            appleErrorMessage = nil
        }
    }

    private var providerButtons: some View {
        VStack(spacing: LeafySpacing.compact) {
            SignInWithAppleButton(.signIn) { request in
                let nonce = Self.randomNonce()
                rawNonce = nonce
                request.requestedScopes = [.email]
                request.nonce = Self.sha256(nonce)
            } onCompletion: { result in handleApple(result) }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .clipShape(.rect(cornerRadius: LeafyRadius.control))

            GoogleAuthenticationButton(purpose: .signInAndLoad)
#if targetEnvironment(simulator)
            Label("Apple sign-in requires a physical iPhone. Email, password, and Google work in Simulator.", systemImage: "iphone.gen3")
                .font(LeafyTypography.caption)
                .foregroundStyle(.secondary)
#endif
        }
    }

    private func signIn() {
        focusedField = nil
        Task { await app.signInAndLoadAccount() }
    }

    private func handleApple(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                appleErrorMessage = "Apple couldn’t complete sign-in. Please try again."
            }
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken,
                  let token = String(data: data, encoding: .utf8), !rawNonce.isEmpty else {
                appleErrorMessage = "Apple didn’t return a valid sign-in credential."
                return
            }
            Task { await app.loadAfterApple(identityToken: token, nonce: rawNonce) }
        }
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in
            var byte: UInt8 = 0
            precondition(SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess)
            return characters[Int(byte) % characters.count]
        })
    }
}

struct AuthField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var contentType: UITextContentType?
    var keyboardType: UIKeyboardType = .default
    let isSecure: Bool
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: LeafySpacing.small) {
            Text(label).font(LeafyTypography.caption).foregroundStyle(.secondary)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(LeafyTypography.body)
            .textContentType(contentType)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
            Rectangle().fill(LeafyTheme.hairline).frame(height: 1)
        }
        .padding(.vertical, LeafySpacing.compact)
    }
}

struct AuthDivider: View {
    var body: some View {
        HStack(spacing: LeafySpacing.compact) {
            Rectangle().fill(LeafyTheme.hairline).frame(height: 1)
            Text("or").font(LeafyTypography.subheadline).foregroundStyle(.secondary)
            Rectangle().fill(LeafyTheme.hairline).frame(height: 1)
        }
    }
}

struct InlineAuthFeedback: View {
    let isLoading: Bool
    let error: String?
    let status: String?

    var body: some View {
        if isLoading {
            HStack(spacing: LeafySpacing.small) {
                ProgressView()
                Text("Working securely…")
            }
            .font(LeafyTypography.footnote)
            .foregroundStyle(.secondary)
        } else if let error {
            Label(error, systemImage: "exclamationmark.circle.fill")
                .font(LeafyTypography.footnote)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if let status {
            Label(status, systemImage: "checkmark.circle.fill")
                .font(LeafyTypography.footnote)
                .foregroundStyle(LeafyTheme.green)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
