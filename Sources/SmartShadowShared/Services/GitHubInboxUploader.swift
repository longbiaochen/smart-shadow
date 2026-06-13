import Foundation

public protocol GitHubContentAPI: AnyObject {
    func putContent(owner: String, repo: String, path: String, data: Data, message: String, token: String) async throws
}

public struct GitHubInboxUploader {
    public var owner: String
    public var repo: String
    public var token: String
    public var inboxPath: String
    public var contentAPI: GitHubContentAPI

    public init(
        owner: String,
        repo: String,
        token: String,
        inboxPath: String = "inbox/pending",
        contentAPI: GitHubContentAPI = GitHubContentsAPIClient()
    ) {
        self.owner = owner
        self.repo = repo
        self.token = token
        self.inboxPath = inboxPath
        self.contentAPI = contentAPI
    }

    public func uploadVoicePacket(_ upload: VoicePacketUpload, now: Date = Date()) async throws -> VoicePacketDelivery {
        _ = upload
        _ = now
        throw GitHubInboxError.legacyAudioUploadDisabled
    }
}

public final class GitHubContentsAPIClient: GitHubContentAPI {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func putContent(owner: String, repo: String, path: String, data: Data, message: String, token: String) async throws {
        let payload: [String: String] = [
            "message": message,
            "content": data.base64EncodedString()
        ]
        var request = request(owner: owner, repo: repo, path: path, token: token)
        request.httpBody = try JSONEncoder().encode(payload)

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw GitHubInboxError.requestFailed(
                status: (response as? HTTPURLResponse)?.statusCode ?? -1,
                body: String(data: responseData, encoding: .utf8) ?? ""
            )
        }
    }

    private func request(owner: String, repo: String, path: String, token: String) -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(owner)/\(repo)/contents/\(path)"

        var request = URLRequest(url: components.url!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("smart-shadow-macos", forHTTPHeaderField: "User-Agent")
        return request
    }
}

public enum GitHubInboxError: LocalizedError, Equatable {
    case requestFailed(status: Int, body: String)
    case missingToken
    case legacyAudioUploadDisabled

    public var errorDescription: String? {
        switch self {
        case let .requestFailed(status, body):
            "GitHub upload failed: HTTP \(status) \(body)"
        case .missingToken:
            "GitHub login is missing."
        case .legacyAudioUploadDisabled:
            "Raw audio GitHub upload is disabled. Process voice locally, confirm the final text, then create an issue or comment."
        }
    }
}
