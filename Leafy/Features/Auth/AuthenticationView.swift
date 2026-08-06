import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

struct AuthenticationView: View {
    private enum EmailMode: String, CaseIterable { case create = "Create account", signIn = "Sign in" }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var rawNonce = ""
    @State private var appleErrorMessage: String?
    @State private var emailMode: EmailMode = .create

    private var isReturningUser: Bool { app.authenticationPurpose == .accessExistingAccount }

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollView {
              VStack(alignment: .leading, spacing: 20) {
                Text(!isReturningUser && emailMode == .create ? "Create your account" : "Welcome back")
                    .font(.largeTitle.bold())
                Text(isReturningUser
                     ? "Sign in to access your saved nutrition plan."
                     : emailMode == .create
                     ? "Save your nutrition targets securely and access them when you return."
                     : "Sign in to save this plan to your existing Leafy account.")
                    .foregroundStyle(.secondary)
                SignInWithAppleButton(.signIn) { request in
                    let nonce = Self.randomNonce(); rawNonce = nonce
                    request.requestedScopes = [.email]
                    request.nonce = Self.sha256(nonce)
                } onCompletion: { result in handleApple(result) }
                .signInWithAppleButtonStyle(.black).frame(height: 52).clipShape(.rect(cornerRadius: 12))
#if targetEnvironment(simulator)
                Label("Test Apple sign-in on a physical iPhone. Email and password work in Simulator.", systemImage: "iphone.gen3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
#endif
                HStack { Rectangle().frame(height: 1).foregroundStyle(.quaternary); Text("or").foregroundStyle(.secondary); Rectangle().frame(height: 1).foregroundStyle(.quaternary) }

                if app.saveState == .awaitingConfirmation {
                    confirmationForm
                } else {
                    if !isReturningUser {
                        Picker("Account action", selection: $emailMode) {
                            ForEach(EmailMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(spacing: 12) {
                        TextField("Email address", text: $app.email)
                            .textContentType(.emailAddress).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        SecureField("Password", text: $app.password)
                            .textContentType(emailMode == .create ? .newPassword : .password)
                            .textFieldStyle(.roundedBorder)
                        if emailMode == .create {
                            SecureField("Confirm password", text: $app.passwordConfirmation)
                                .textContentType(.newPassword)
                                .textFieldStyle(.roundedBorder)
                            Text("Use at least 8 characters.")
                                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Button(primaryButtonTitle) {
                        Task {
                            if isReturningUser { await app.signInAndLoadAccount() }
                            else if emailMode == .create { await app.createAccount() }
                            else { await app.signInAndSave() }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                if app.saveState != .idle && app.saveState != .awaitingConfirmation && app.saveState != .resendingConfirmation {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if let error = appleErrorMessage ?? app.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Text("By continuing, you agree to Leafy’s Terms and acknowledge its Privacy Policy.").font(.caption).foregroundStyle(.secondary)
              }.padding(24)
            }
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
        .interactiveDismissDisabled(app.saveState == .saving)
        .onAppear {
            app.errorMessage = nil
            appleErrorMessage = nil
            if isReturningUser { emailMode = .signIn }
        }
    }

    private var primaryButtonTitle: String {
        if isReturningUser { return "Sign in" }
        return emailMode == .create ? "Create account and save" : "Sign in and save"
    }

    private var confirmationForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Check your email", systemImage: "envelope.badge")
                .font(.title2.bold()).foregroundStyle(.tint)
            Text("We created your account and sent a confirmation link to **\(app.email)**. Tap the link in that email, then return here to finish saving your plan.")
                .foregroundStyle(.secondary)
            Label("After confirming, come back to Leafy—even if the browser opens a blank or localhost page.", systemImage: "arrow.uturn.backward.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("I've confirmed my email") { Task { await app.finishConfirmedAccount() } }
                .buttonStyle(PrimaryButtonStyle())
            Button {
                Task { await app.resendAccountConfirmation() }
            } label: {
                if app.saveState == .resendingConfirmation {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Sending…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("Resend confirmation email").frame(maxWidth: .infinity)
                }
            }
            .disabled(app.saveState == .resendingConfirmation)
            if let message = app.statusMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            Button("Use a different email") {
                app.saveState = .idle
                app.errorMessage = nil
                app.statusMessage = nil
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case let .failure(error):
            let authorizationError = error as? ASAuthorizationError
            if authorizationError?.code == .canceled { return }
#if targetEnvironment(simulator)
            appleErrorMessage = "Sign in with Apple isn’t available in this simulator. Use email verification below or test it on your iPhone."
#else
            appleErrorMessage = "Apple couldn’t complete sign-in. Try again or use email verification below."
#endif
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken, let token = String(data: data, encoding: .utf8), !rawNonce.isEmpty
            else { app.errorMessage = "Apple did not return a valid identity token."; return }
            Task {
                if isReturningUser {
                    await app.loadAfterApple(identityToken: token, nonce: rawNonce)
                } else {
                    await app.saveAfterApple(identityToken: token, nonce: rawNonce)
                }
            }
        }
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in
            var byte: UInt8 = 0; let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            precondition(status == errSecSuccess)
            return characters[Int(byte) % characters.count]
        })
    }
}
