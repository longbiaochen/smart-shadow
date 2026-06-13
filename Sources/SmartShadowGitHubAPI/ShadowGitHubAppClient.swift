import Foundation

public struct ShadowGitHubAppClient: Sendable {
    public var installationToken: String
    public var session: URLSession
    public var userAgent: String

    public init(
        installationToken: String,
        session: URLSession = .shared,
        userAgent: String = "smart-shadow-shadow-app"
    ) {
        self.installationToken = installationToken
        self.session = session
        self.userAgent = userAgent
    }

    public func commentIssue(repoFullName: String, issueNumber: Int, body: String) async throws {
        try await sendWithoutBodyResponse(
            path: "/repos/\(repoFullName)/issues/\(issueNumber)/comments",
            method: "POST",
            body: ShadowAppCommentRequest(body: body)
        )
    }

    public func updateIssueTitle(repoFullName: String, issueNumber: Int, title: String) async throws {
        try await sendWithoutBodyResponse(
            path: "/repos/\(repoFullName)/issues/\(issueNumber)",
            method: "PATCH",
            body: ShadowAppIssueUpdateRequest(title: title, labels: nil)
        )
    }

    public func setLabels(repoFullName: String, issueNumber: Int, labels: [String]) async throws {
        try await sendWithoutBodyResponse(
            path: "/repos/\(repoFullName)/issues/\(issueNumber)",
            method: "PATCH",
            body: ShadowAppIssueUpdateRequest(title: nil, labels: labels)
        )
    }

    public func createBranch(repoFullName: String, branchName: String, fromSHA: String) async throws {
        try await sendWithoutBodyResponse(
            path: "/repos/\(repoFullName)/git/refs",
            method: "POST",
            body: ShadowAppCreateRefRequest(ref: "refs/heads/\(branchName)", sha: fromSHA)
        )
    }

    public func createPullRequest(repoFullName: String, title: String, head: String, base: String, body: String) async throws {
        try await sendWithoutBodyResponse(
            path: "/repos/\(repoFullName)/pulls",
            method: "POST",
            body: ShadowAppPullRequestRequest(title: title, head: head, base: base, body: body)
        )
    }

    private func sendWithoutBodyResponse<T: Encodable>(
        path: String,
        method: String,
        body: T
    ) async throws {
        let data = try Self.encoder.encode(body)
        let request = try makeRequest(path: path, method: method, bodyData: data)
        let (responseData, response) = try await session.data(for: request)
        try validate(response: response, data: responseData)
    }

    private func makeRequest(path: String, method: String, bodyData: Data?) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.percentEncodedPath = path
        guard let url = components.url else {
            throw GitHubAPIError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        request.setValue("Bearer \(installationToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GitHubAPIError.requestFailed(statusCode: -1, body: "")
        }
        guard 200..<300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubAPIError.requestFailed(statusCode: http.statusCode, body: body)
        }
    }

    private static let encoder = JSONEncoder()
}

private struct ShadowAppCommentRequest: Encodable {
    var body: String
}

private struct ShadowAppIssueUpdateRequest: Encodable {
    var title: String?
    var labels: [String]?
}

private struct ShadowAppCreateRefRequest: Encodable {
    var ref: String
    var sha: String
}

private struct ShadowAppPullRequestRequest: Encodable {
    var title: String
    var head: String
    var base: String
    var body: String
}
