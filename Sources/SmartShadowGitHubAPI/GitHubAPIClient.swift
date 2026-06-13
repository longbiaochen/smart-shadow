import Foundation

public struct GitHubAPIRepository: Decodable, Sendable, Equatable {
    public var id: Int
    public var name: String
    public var fullName: String
    public var description: String?
    public var openIssuesCount: Int
    public var updatedAt: Date
    public var topics: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case description
        case openIssuesCount = "open_issues_count"
        case updatedAt = "updated_at"
        case topics
    }
}

public struct GitHubAPIIssue: Decodable, Sendable, Equatable {
    public var id: Int
    public var number: Int
    public var title: String
    public var state: String
    public var labels: [GitHubAPILabel]
    public var assignee: GitHubAPIAssignee?
    public var updatedAt: Date
    public var comments: Int
    public var pullRequest: GitHubAPIPullRequestMarker?
    public var body: String?

    public var isPullRequest: Bool {
        pullRequest != nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case state
        case labels
        case assignee
        case updatedAt = "updated_at"
        case comments
        case pullRequest = "pull_request"
        case body
    }
}

public struct GitHubAPILabel: Decodable, Sendable, Equatable {
    public var name: String
}

public struct GitHubAPIAssignee: Decodable, Sendable, Equatable {
    public var login: String
}

public struct GitHubAPIPullRequestMarker: Decodable, Sendable, Equatable {}

public struct GitHubAPIIssueComment: Decodable, Sendable, Equatable {
    public var id: Int
    public var body: String?
    public var user: GitHubAPIAssignee?
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case user
        case updatedAt = "updated_at"
    }
}

public enum GitHubAPIError: Error, Equatable {
    case invalidURL(String)
    case requestFailed(statusCode: Int, body: String)
}

public struct GitHubAPIClient: Sendable {
    public var token: String
    public var session: URLSession
    public var userAgent: String

    public init(token: String, session: URLSession = .shared, userAgent: String = "smart-shadow") {
        self.token = token
        self.session = session
        self.userAgent = userAgent
    }

    public func fetchRepositories() async throws -> [GitHubAPIRepository] {
        try await send(
            path: "/user/repos?affiliation=owner,collaborator,organization_member&sort=updated&per_page=60",
            method: "GET",
            as: [GitHubAPIRepository].self
        )
    }

    public func fetchIssues(repoFullName: String) async throws -> [GitHubAPIIssue] {
        try await send(
            path: "/repos/\(repoFullName)/issues?state=open&per_page=40",
            method: "GET",
            as: [GitHubAPIIssue].self
        )
    }

    public func fetchIssueComments(repoFullName: String, issueNumber: Int) async throws -> [GitHubAPIIssueComment] {
        try await send(
            path: "/repos/\(repoFullName)/issues/\(issueNumber)/comments?per_page=20",
            method: "GET",
            as: [GitHubAPIIssueComment].self
        )
    }

    public func fetchPullCount(repoFullName: String) async throws -> Int {
        let pulls = try await send(
            path: "/repos/\(repoFullName)/pulls?state=open&per_page=100",
            method: "GET",
            as: [GitHubAPIPull].self
        )
        return pulls.count
    }

    public func createIssueComment(repoFullName: String, issueNumber: Int, body: String) async throws {
        try await sendWithoutBodyResponse(
            path: "/repos/\(repoFullName)/issues/\(issueNumber)/comments",
            method: "POST",
            body: GitHubAPICommentRequest(body: body)
        )
    }

    public func createIssue(repoFullName: String, title: String, body: String, labels: [String] = []) async throws {
        try await sendWithoutBodyResponse(
            path: "/repos/\(repoFullName)/issues",
            method: "POST",
            body: GitHubAPICreateIssueRequest(title: title, body: body, labels: labels)
        )
    }

    public func createRepository(name: String, description: String?) async throws {
        try await sendWithoutBodyResponse(
            path: "/user/repos",
            method: "POST",
            body: GitHubAPICreateRepositoryRequest(name: name, description: description, isPrivate: true, autoInit: true)
        )
    }

    private func send<T: Decodable>(
        path: String,
        method: String,
        as type: T.Type
    ) async throws -> T {
        let request = try makeRequest(path: path, method: method, bodyData: nil)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try Self.decoder.decode(T.self, from: data)
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
        components.percentEncodedPath = path.split(separator: "?").first.map(String.init) ?? path
        if let query = path.split(separator: "?", maxSplits: 1).dropFirst().first {
            components.percentEncodedQuery = String(query)
        }
        guard let url = components.url else {
            throw GitHubAPIError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if bodyData != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
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

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder = JSONEncoder()
}

private struct GitHubAPIPull: Decodable {
    var id: Int
}

private struct GitHubAPICommentRequest: Encodable {
    var body: String
}

private struct GitHubAPICreateIssueRequest: Encodable {
    var title: String
    var body: String
    var labels: [String]
}

private struct GitHubAPICreateRepositoryRequest: Encodable {
    var name: String
    var description: String?
    var isPrivate: Bool
    var autoInit: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case isPrivate = "private"
        case autoInit = "auto_init"
    }
}
