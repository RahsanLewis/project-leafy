import XCTest
@testable import Leafy

final class AccountDeletionTests: XCTestCase {
    func testAppleIdentityDetectionIsProviderSpecific() {
        let apple = LeafyAccount(
            userID: UUID(),
            email: "leafy@example.com",
            emailConfirmed: true,
            identities: [
                AccountIdentity(id: "1", provider: "apple", email: "leafy@example.com"),
                AccountIdentity(id: "2", provider: "email", email: "leafy@example.com"),
            ]
        )
        let google = LeafyAccount(
            userID: UUID(),
            email: "leafy@example.com",
            emailConfirmed: true,
            identities: [AccountIdentity(id: "1", provider: "google", email: "leafy@example.com")]
        )
        let emailOnly = LeafyAccount(
            userID: UUID(),
            email: "leafy@example.com",
            emailConfirmed: true,
            identities: [AccountIdentity(id: "1", provider: "email", email: "leafy@example.com")]
        )

        XCTAssertTrue(apple.hasAppleIdentity)
        XCTAssertFalse(google.hasAppleIdentity)
        XCTAssertFalse(emailOnly.hasAppleIdentity)
        XCTAssertTrue(
            LeafyAccount(
                userID: UUID(),
                email: nil,
                emailConfirmed: false,
                identities: [AccountIdentity(id: "1", provider: "Apple", email: nil)]
            ).hasAppleIdentity
        )
    }

    func testDeleteAccountRequestSendsAuthorizationCodeAndNeverIdentityToken() throws {
        XCTAssertEqual(AccountDeletion.requestPayload(appleAuthorizationCode: nil), [:])
        XCTAssertEqual(AccountDeletion.requestPayload(appleAuthorizationCode: "   "), [:])
        XCTAssertEqual(
            AccountDeletion.requestPayload(appleAuthorizationCode: "  auth-code-value  "),
            ["apple_authorization_code": "auth-code-value"]
        )

        let object = AccountDeletion.requestPayload(appleAuthorizationCode: "auth-code-value")
        XCTAssertNil(object["identity_token"])
        XCTAssertNil(object["identityToken"])
        XCTAssertEqual(object["apple_authorization_code"], "auth-code-value")
    }

    func testAuthorizationCodeExtractionUsesUTF8DataNotIdentityToken() {
        let authorizationCode = AccountDeletion.utf8AuthorizationCode(from: Data("fresh-apple-code".utf8))
        let identityToken = AccountDeletion.utf8AuthorizationCode(from: Data("identity-token-value".utf8))

        XCTAssertEqual(authorizationCode, "fresh-apple-code")
        XCTAssertNotEqual(authorizationCode, identityToken)
        XCTAssertNil(AccountDeletion.utf8AuthorizationCode(from: Data()))
        XCTAssertNil(AccountDeletion.utf8AuthorizationCode(from: nil))
    }

    func testSuccessResponseDecodesAppleRevokeFields() throws {
        let json = """
        {
          "ok": true,
          "deleted": true,
          "apple_identity": true,
          "apple_revoked": true,
          "apple_revoke_error": null,
          "errors": [],
          "storage_objects_removed": 3
        }
        """
        let response = try JSONDecoder().decode(DeleteAccountResponse.self, from: Data(json.utf8))
        XCTAssertTrue(response.ok)
        XCTAssertTrue(response.deleted)
        XCTAssertTrue(response.appleIdentity)
        XCTAssertTrue(response.appleRevoked)
        XCTAssertNil(response.appleRevokeError)
        XCTAssertEqual(response.storageObjectsRemoved, 3)
        XCTAssertFalse(AccountDeletion.shouldWarnAboutFailedAppleRevoke(hadAppleIdentity: true, response: response))
    }

    func testPartialSuccessWarnsWhenAppleRevokeFailed() throws {
        let json = """
        {
          "ok": true,
          "deleted": true,
          "apple_identity": true,
          "apple_revoked": false,
          "apple_revoke_error": "revoke_failed",
          "errors": ["Apple token revocation failed; the Leafy account was still deleted."]
        }
        """
        let response = try JSONDecoder().decode(DeleteAccountResponse.self, from: Data(json.utf8))
        XCTAssertTrue(response.deleted)
        XCTAssertFalse(response.appleRevoked)
        XCTAssertEqual(response.appleRevokeError, "revoke_failed")
        XCTAssertTrue(AccountDeletion.shouldWarnAboutFailedAppleRevoke(hadAppleIdentity: true, response: response))
        XCTAssertTrue(
            AccountDeletion.appleRevokeFailedNotice.contains("Apple credential cleanup failed")
        )
        XCTAssertTrue(
            AccountDeletion.appleRevokeFailedNotice.contains("Apple ID settings")
        )
    }

    func testNonAppleSuccessDoesNotWarnWhenAppleRevokedIsFalse() throws {
        let json = """
        {
          "ok": true,
          "deleted": true,
          "apple_identity": false,
          "apple_revoked": false,
          "apple_revoke_error": null,
          "errors": []
        }
        """
        let response = try JSONDecoder().decode(DeleteAccountResponse.self, from: Data(json.utf8))
        XCTAssertFalse(AccountDeletion.shouldWarnAboutFailedAppleRevoke(hadAppleIdentity: false, response: response))
    }

    func testFailureBodyDecodesErrorCodeWithoutClaimingDeletion() throws {
        let json = """
        {
          "ok": false,
          "error": "Apple Sign in must be confirmed before deleting this account.",
          "error_code": "apple_authorization_code_required",
          "apple_identity": true,
          "apple_revoked": false,
          "apple_revoke_error": "missing_authorization_code",
          "errors": ["Apple Sign in must be confirmed before deleting this account."]
        }
        """
        let response = try JSONDecoder().decode(DeleteAccountResponse.self, from: Data(json.utf8))
        XCTAssertFalse(response.ok)
        XCTAssertFalse(response.deleted)
        XCTAssertEqual(response.errorCode, "apple_authorization_code_required")
        XCTAssertEqual(
            AccountDeletion.notDeletedMessage(statusCode: 409, serverMessage: response.error ?? ""),
            "Your Leafy account was not deleted. Confirm Sign in with Apple and try again."
        )
        XCTAssertEqual(
            AccountDeletion.notDeletedMessage(statusCode: 503, serverMessage: "ignored"),
            "Your Leafy account was not deleted. Apple credential cleanup isn’t available right now. Try again later."
        )
        XCTAssertTrue(
            AccountDeletion.notDeletedMessage(
                statusCode: 500,
                serverMessage: "Unable to delete account media."
            ).contains("was not deleted")
        )
    }

    func testServiceErrorPreservesHTTPStatusForDeleteFailures() {
        let conflict = PlanService.ServiceError.invalidResponse(409, "Apple Sign in must be confirmed before deleting this account.")
        let unavailable = PlanService.ServiceError.invalidResponse(503, "Apple account revocation is not configured. Try again later.")
        let purgeFailed = PlanService.ServiceError.invalidResponse(500, "Unable to delete account media.")

        XCTAssertEqual(conflict.httpStatusCode, 409)
        XCTAssertEqual(unavailable.httpStatusCode, 503)
        XCTAssertEqual(purgeFailed.httpStatusCode, 500)
    }
}
