import XCTest
@testable import SmartShadowGitHubAPI
@testable import SmartShadowIOS

final class GitHubOAuthServiceTests: XCTestCase {
    func testDeviceCodeResponseParsesGitHubPayload() throws {
        let json = """
        {
          "device_code": "device-123",
          "user_code": "ABCD-EFGH",
          "verification_uri": "https://github.com/login/device",
          "expires_in": 900,
          "interval": 5
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(GitHubOAuthDeviceCodeResponse.self, from: json)

        XCTAssertEqual(response.deviceCode, "device-123")
        XCTAssertEqual(response.userCode, "ABCD-EFGH")
        XCTAssertEqual(response.verificationURI.absoluteString, "https://github.com/login/device")
        XCTAssertEqual(response.expiresIn, 900)
        XCTAssertEqual(response.interval, 5)
    }

    func testTokenResponseParsesAccessToken() throws {
        let json = """
        {
          "access_token": "gho_token",
          "token_type": "bearer",
          "scope": "repo,read:user"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(GitHubOAuthTokenResponse.self, from: json)

        XCTAssertEqual(GitHubOAuthPollResult.parse(response), .token("gho_token"))
    }

    func testPollResultClassifiesGitHubErrors() {
        XCTAssertEqual(GitHubOAuthPollResult.parse(.init(error: "authorization_pending")), .pending)
        XCTAssertEqual(GitHubOAuthPollResult.parse(.init(error: "slow_down")), .slowDown)
        XCTAssertEqual(GitHubOAuthPollResult.parse(.init(error: "expired_token")), .expired)
        XCTAssertEqual(GitHubOAuthPollResult.parse(.init(error: "access_denied")), .denied)
        XCTAssertEqual(GitHubOAuthPollResult.parse(.init(error: "bad_verification_code", errorDescription: "Bad code")), .failed("Bad code"))
    }

    func testVoiceInteractionStateTextAndScale() {
        XCTAssertEqual(VoiceInteractionState.idle.statusText, "按住，说给影子听")
        XCTAssertEqual(VoiceInteractionState.listening.statusText, "松开发送")
        XCTAssertEqual(VoiceInteractionState.uploading.statusText, "正在送达影子...")
        XCTAssertGreaterThan(VoiceInteractionState.listening.orbScale, VoiceInteractionState.idle.orbScale)
    }
}

private extension GitHubOAuthTokenResponse {
    init(error: String, errorDescription: String? = nil) {
        self.init(accessToken: nil, tokenType: nil, scope: nil, error: error, errorDescription: errorDescription)
    }
}
