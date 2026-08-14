import Foundation
import LocalAuthentication
import Observation
import UIKit

@MainActor @Observable
final class AppLockCoordinator {
    static let enabledKey = "leafy.appLock.enabled"
    private static let backgroundDateKey = "leafy.appLock.backgroundDate"
    private let defaults: UserDefaults

    var isLocked = false
    var errorMessage: String?
    var isAuthenticating = false

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    var biometricName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .faceID ? "Face ID" : "device authentication"
    }

    func enable() async -> Bool {
        guard await authenticate(reason: "Protect your Leafy health data") else { return false }
        isEnabled = true
        isLocked = false
        return true
    }

    func disable() async -> Bool {
        guard await authenticate(reason: "Turn off Leafy app protection") else { return false }
        isEnabled = false
        isLocked = false
        return true
    }

    func sceneDidEnterBackground() {
        defaults.set(Date().timeIntervalSince1970, forKey: Self.backgroundDateKey)
    }

    func sceneDidBecomeActive() {
        guard isEnabled else { isLocked = false; return }
        let background = defaults.double(forKey: Self.backgroundDateKey)
        if background == 0 || Date().timeIntervalSince1970 - background >= 60 { isLocked = true }
    }

    func unlock() async { if await authenticate(reason: "Unlock Leafy") { isLocked = false } }

    private func authenticate(reason: String) async -> Bool {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        do {
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
                errorMessage = "Set up Face ID or a device passcode to protect Leafy."
                return false
            }
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            errorMessage = "Leafy is still locked."
            return false
        }
    }
}
