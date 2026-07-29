import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

struct AuthenticationView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var rawNonce = ""

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Save your plan").font(.largeTitle.bold())
                Text("Create a secure account so your targets are available when you return.").foregroundStyle(.secondary)
                SignInWithAppleButton(.signIn) { request in
                    let nonce = Self.randomNonce(); rawNonce = nonce
                    request.requestedScopes = [.email]
                    request.nonce = Self.sha256(nonce)
                } onCompletion: { result in handleApple(result) }
                .signInWithAppleButtonStyle(.black).frame(height: 52).clipShape(.rect(cornerRadius: 12))
                HStack { Rectangle().frame(height: 1).foregroundStyle(.quaternary); Text("or").foregroundStyle(.secondary); Rectangle().frame(height: 1).foregroundStyle(.quaternary) }
                TextField("Email address", text: $app.email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                if app.saveState == .awaitingCode {
                    TextField("Six-digit code", text: $app.emailCode).keyboardType(.numberPad).textContentType(.oneTimeCode).textFieldStyle(.roundedBorder)
                    Button("Verify and save") { Task { await app.verifyCodeAndSave() } }.buttonStyle(PrimaryButtonStyle())
                    Button("Send a new code") { Task { await app.sendCode() } }.frame(maxWidth: .infinity)
                } else {
                    Button("Email me a code") { Task { await app.sendCode() } }.buttonStyle(PrimaryButtonStyle())
                }
                if app.saveState != .idle && app.saveState != .awaitingCode { ProgressView().frame(maxWidth: .infinity) }
                if let error = app.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                Text("By continuing, you agree to Leafy’s Terms and acknowledge its Privacy Policy.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(24)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .interactiveDismissDisabled(app.saveState == .saving)
    }

    private func handleApple(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case let .failure(error): app.errorMessage = error.localizedDescription
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken, let token = String(data: data, encoding: .utf8), !rawNonce.isEmpty
            else { app.errorMessage = "Apple did not return a valid identity token."; return }
            Task { await app.saveAfterApple(identityToken: token, nonce: rawNonce) }
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

