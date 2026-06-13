import Foundation

public enum ShadowGitHubActionExecutionResult: Equatable {
    case executed
    case missingAction
    case missingToken
    case missingIssueNumber
    case missingRepoName
    case failed

    public var statusMessage: String {
        switch self {
        case .executed:
            "GitHub action executed."
        case .missingAction:
            "No confirmed GitHub action is ready."
        case .missingToken:
            "GitHub login required before executing writes."
        case .missingIssueNumber:
            "Issue number missing for comment action."
        case .missingRepoName:
            "Repo name missing for create repo action."
        case .failed:
            "GitHub action failed. Check token permissions and network state."
        }
    }
}

public protocol ShadowGitHubWriteClient {
    func createIssueComment(repoFullName: String, issueNumber: Int, body: String) async throws
    func createIssue(repoFullName: String, title: String, body: String, labels: [String]) async throws
    func createRepository(name: String, description: String?) async throws
}

public enum ShadowGitHubActionExecutor {
    public static func execute(
        plan: ShadowGitHubActionPlan?,
        token: String,
        client: any ShadowGitHubWriteClient
    ) async -> ShadowGitHubActionExecutionResult {
        guard let plan else {
            return .missingAction
        }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .missingToken
        }

        do {
            switch plan.kind {
            case .issueComment:
                guard let issueNumber = plan.issueNumber else {
                    return .missingIssueNumber
                }
                try await client.createIssueComment(
                    repoFullName: plan.repoFullName,
                    issueNumber: issueNumber,
                    body: plan.body
                )
            case .createIssue:
                try await client.createIssue(
                    repoFullName: plan.repoFullName,
                    title: plan.issueTitle ?? plan.title,
                    body: plan.body,
                    labels: plan.labels
                )
            case .createRepo:
                guard let repoName = plan.repoName else {
                    return .missingRepoName
                }
                try await client.createRepository(name: repoName, description: plan.repoDescription)
            }
            return .executed
        } catch {
            return .failed
        }
    }
}
