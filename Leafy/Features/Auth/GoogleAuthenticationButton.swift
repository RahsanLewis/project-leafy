import GoogleSignIn
import GoogleSignInSwift
import SwiftUI
import UIKit

struct GoogleAuthenticationButton: View {
    enum Purpose { case createAndSave, signInAndLoad }
    @Environment(AppCoordinator.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    let purpose: Purpose
    var isEnabled = true
    @State private var errorMessage: String?
    @State private var isSigningIn = false

    var body: some View {
        GoogleSignInButton(
            scheme: colorScheme == .dark ? .dark : .light,
            style: .wide,
            state: isAvailable && isEnabled ? .normal : .disabled
        ) {
            Task { await signIn() }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .disabled(!isAvailable || !isEnabled)
        .overlay(alignment: .trailing) {
            if isSigningIn {
                ProgressView()
                    .padding(.trailing, 16)
                    .accessibilityLabel("Signing in with Google")
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !app.configuration.isGoogleConfigured {
                Text("Google setup required").font(LeafyTypography.caption).foregroundStyle(.secondary).offset(y: 17)
            }
        }
        .alert("Google sign-in unavailable", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: { Text(errorMessage ?? "") }
    }

    private var isAvailable: Bool { app.configuration.isGoogleConfigured && !isSigningIn }

    @MainActor private func signIn() async {
        guard isAvailable else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            errorMessage = "Leafy could not present Google sign-in. Try again."
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: app.configuration.googleIOSClientID,
            serverClientID: app.configuration.googleServerClientID
        )
        do {
            let rawNonce = OAuthNonce.generate()
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: nil,
                nonce: OAuthNonce.sha256(rawNonce)
            )
            guard let token = result.user.idToken?.tokenString else {
                errorMessage = "Google did not return a secure identity token."
                return
            }
            let accessToken = result.user.accessToken.tokenString
            if purpose == .createAndSave {
                await app.saveAfterGoogle(identityToken: token, accessToken: accessToken, nonce: rawNonce)
            } else {
                await app.loadAfterGoogle(identityToken: token, accessToken: accessToken, nonce: rawNonce)
            }
        } catch {
            if (error as NSError).code != GIDSignInError.canceled.rawValue {
                errorMessage = "Google couldn’t complete sign-in. Try again."
            }
        }
    }
}
