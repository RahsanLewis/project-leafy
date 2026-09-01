import Foundation

struct DeleteAccountResponse: Decodable, Equatable, Sendable {
    var ok: Bool
    var deleted: Bool
    var appleIdentity: Bool
    var appleRevoked: Bool
    var appleRevokeError: String?
    var error: String?
    var errorCode: String?
    var errors: [String]
    var storageObjectsRemoved: Int?

    init(
        ok: Bool,
        deleted: Bool,
        appleIdentity: Bool,
        appleRevoked: Bool,
        appleRevokeError: String? = nil,
        error: String? = nil,
        errorCode: String? = nil,
        errors: [String] = [],
        storageObjectsRemoved: Int? = nil
    ) {
        self.ok = ok
        self.deleted = deleted
        self.appleIdentity = appleIdentity
        self.appleRevoked = appleRevoked
        self.appleRevokeError = appleRevokeError
        self.error = error
        self.errorCode = errorCode
        self.errors = errors
        self.storageObjectsRemoved = storageObjectsRemoved
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        appleIdentity = try container.decodeIfPresent(Bool.self, forKey: .appleIdentity) ?? false
        appleRevoked = try container.decodeIfPresent(Bool.self, forKey: .appleRevoked) ?? false
        appleRevokeError = try container.decodeIfPresent(String.self, forKey: .appleRevokeError)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        errorCode = try container.decodeIfPresent(String.self, forKey: .errorCode)
        errors = try container.decodeIfPresent([String].self, forKey: .errors) ?? []
        storageObjectsRemoved = try container.decodeIfPresent(Int.self, forKey: .storageObjectsRemoved)
    }

    private enum CodingKeys: String, CodingKey {
        case ok, deleted, error, errors
        case appleIdentity = "apple_identity"
        case appleRevoked = "apple_revoked"
        case appleRevokeError = "apple_revoke_error"
        case errorCode = "error_code"
        case storageObjectsRemoved = "storage_objects_removed"
    }
}

enum AccountDeletion {
    static let appleRevokeFailedNotice =
        "Your Leafy account was deleted, but Apple credential cleanup failed. You may need to remove Leafy from Apple ID settings."

    static func requestPayload(appleAuthorizationCode: String?) -> [String: String] {
        guard let code = utf8AuthorizationCode(appleAuthorizationCode), !code.isEmpty else {
            return [:]
        }
        return ["apple_authorization_code": code]
    }

    static func utf8AuthorizationCode(_ value: String?) -> String? {
        let code = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return code.isEmpty ? nil : code
    }

    static func utf8AuthorizationCode(from data: Data?) -> String? {
        guard let data, let value = String(data: data, encoding: .utf8) else { return nil }
        return utf8AuthorizationCode(value)
    }

    static func shouldWarnAboutFailedAppleRevoke(
        hadAppleIdentity: Bool,
        response: DeleteAccountResponse
    ) -> Bool {
        (hadAppleIdentity || response.appleIdentity) && !response.appleRevoked
    }

    static func notDeletedMessage(statusCode: Int?, serverMessage: String) -> String {
        let notDeleted = "Your Leafy account was not deleted."
        switch statusCode {
        case 409:
            return "\(notDeleted) Confirm Sign in with Apple and try again."
        case 503:
            return "\(notDeleted) Apple credential cleanup isn’t available right now. Try again later."
        default:
            let detail = serverMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "\(notDeleted) Try again in a moment."
            }
            return "\(notDeleted) \(detail)"
        }
    }
}

extension PlanService.ServiceError {
    var httpStatusCode: Int? {
        if case let .invalidResponse(code, _) = self { return code }
        return nil
    }
}
