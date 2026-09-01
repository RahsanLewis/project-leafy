import AuthenticationServices
import UIKit

enum AppleAuthorizationCodeError: LocalizedError, Equatable {
    case canceled
    case missingAuthorizationCode
    case presentationFailed

    var errorDescription: String? {
        switch self {
        case .canceled:
            nil
        case .missingAuthorizationCode:
            "Apple didn’t return an authorization code. Try again."
        case .presentationFailed:
            "Leafy couldn’t present Sign in with Apple. Try again."
        }
    }
}

/// Requests a fresh Sign in with Apple authorization code for account deletion.
/// This is not a login: nonce and identity token are intentionally unused.
@MainActor
enum AppleAuthorizationCodeRequest {
    private static var activeCoordinator: Coordinator?

    static func authorizationCode() async throws -> String {
        let coordinator = Coordinator()
        activeCoordinator = coordinator
        defer { activeCoordinator = nil }
        return try await coordinator.requestAuthorizationCode()
    }
}

@MainActor
private final class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String, Error>?
    private var controller: ASAuthorizationController?

    func requestAuthorizationCode() async throws -> String {
        guard presentationWindow() != nil else {
            throw AppleAuthorizationCodeError.presentationFailed
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        presentationWindow() ?? ASPresentationAnchor()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        // Never send identityToken; only the UTF-8 authorizationCode is valid for revoke.
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let code = AccountDeletion.utf8AuthorizationCode(from: credential.authorizationCode) else {
            finish(throwing: AppleAuthorizationCodeError.missingAuthorizationCode)
            return
        }
        finish(returning: code)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if (error as? ASAuthorizationError)?.code == .canceled {
            finish(throwing: AppleAuthorizationCodeError.canceled)
            return
        }
        finish(throwing: error)
    }

    private func presentationWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    private func finish(returning code: String) {
        continuation?.resume(returning: code)
        continuation = nil
        controller = nil
    }

    private func finish(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        controller = nil
    }
}
