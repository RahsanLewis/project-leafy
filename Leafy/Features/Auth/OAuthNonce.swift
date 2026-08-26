import CryptoKit
import Foundation
import Security

enum OAuthNonce {
    private static let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    static func generate(length: Int = 32) -> String {
        precondition(length > 0)
        precondition(characters.count == 64)

        var bytes = [UInt8](repeating: 0, count: length)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        precondition(status == errSecSuccess, "Unable to generate a secure OAuth nonce.")

        return String(bytes.map { characters[Int($0) & 63] })
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
