import Foundation

public struct GitHubOAuthDeviceCodeResponse: Decodable, Equatable, Sendable {
    public var deviceCode: String
    public var userCode: String
    public var verificationURI: URL
    public var expiresIn: Int
    public var interval: Int

    public init(deviceCode: String, userCode: String, verificationURI: URL, expiresIn: Int, interval: Int) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.expiresIn = expiresIn
        self.interval = interval
    }

    public enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

public struct GitHubOAuthTokenResponse: Decodable, Equatable, Sendable {
    public var accessToken: String?
    public var tokenType: String?
    public var scope: String?
    public var error: String?
    public var errorDescription: String?

    public init(accessToken: String? = nil, tokenType: String? = nil, scope: String? = nil, error: String? = nil, errorDescription: String? = nil) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.scope = scope
        self.error = error
        self.errorDescription = errorDescription
    }

    public enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case error
        case errorDescription = "error_description"
    }
}

public enum GitHubOAuthPollResult: Equatable, Sendable {
    case token(String)
    case pending
    case slowDown
    case expired
    case denied
    case failed(String)

    public static func parse(_ response: GitHubOAuthTokenResponse) -> GitHubOAuthPollResult {
        if let token = response.accessToken, !token.isEmpty {
            return .token(token)
        }

        switch response.error {
        case "authorization_pending":
            return .pending
        case "slow_down":
            return .slowDown
        case "expired_token":
            return .expired
        case "access_denied":
            return .denied
        case let error?:
            return .failed(response.errorDescription ?? error)
        case nil:
            return .failed("GitHub did not return an access token.")
        }
    }
}

public struct GitHubUser: Decodable, Equatable, Sendable {
    public var login: String

    public init(login: String) {
        self.login = login
    }
}

public enum GitHubOAuthError: LocalizedError, Equatable, Sendable {
    case missingClientID
    case requestFailed(Int, String)
    case expired
    case denied
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .missingClientID:
            "GitHub OAuth Client ID is missing."
        case let .requestFailed(status, body):
            "GitHub OAuth request failed: HTTP \(status) \(body)"
        case .expired:
            "GitHub login code expired."
        case .denied:
            "GitHub login was denied."
        case let .failed(message):
            message
        }
    }
}

public struct GitHubOAuthService: Sendable {
    private var session: URLSession
    private var userAgent: String

    public init(session: URLSession = .shared, userAgent: String = "smart-shadow") {
        self.session = session
        self.userAgent = userAgent
    }

    public func requestDeviceCode(clientID: String, scopes: [String] = ["repo", "read:user"]) async throws -> GitHubOAuthDeviceCodeResponse {
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { throw GitHubOAuthError.missingClientID }

        let body = formBody([
            "client_id": clientID,
            "scope": scopes.joined(separator: " ")
        ])
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        return try await send(request, as: GitHubOAuthDeviceCodeResponse.self)
    }

    public func pollForAccessToken(clientID: String, deviceCode: String, interval: Int, expiresIn: Int) async throws -> String {
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
        var pollInterval = max(interval, 5)

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(pollInterval) * 1_000_000_000)

            let body = formBody([
                "client_id": clientID,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ])
            var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.httpBody = body

            let response = try await send(request, as: GitHubOAuthTokenResponse.self)
            switch GitHubOAuthPollResult.parse(response) {
            case let .token(token):
                return token
            case .pending:
                continue
            case .slowDown:
                pollInterval += 5
            case .expired:
                throw GitHubOAuthError.expired
            case .denied:
                throw GitHubOAuthError.denied
            case let .failed(message):
                throw GitHubOAuthError.failed(message)
            }
        }

        throw GitHubOAuthError.expired
    }

    public func validateUser(token: String) async throws -> GitHubUser {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try await send(request, as: GitHubUser.self)
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw GitHubOAuthError.requestFailed(
                (response as? HTTPURLResponse)?.statusCode ?? -1,
                String(data: data, encoding: .utf8) ?? ""
            )
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func formBody(_ values: [String: String]) -> Data {
        let body = values
            .map { key, value in "\(urlEncode(key))=\(urlEncode(value))" }
            .sorted()
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}
