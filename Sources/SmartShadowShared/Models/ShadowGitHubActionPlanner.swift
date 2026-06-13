import Foundation

public enum PlannedGitHubActionKind: String, Equatable {
    case issueComment
    case createIssue
    case createRepo
}

public struct ShadowGitHubActionPlan: Equatable {
    public var kind: PlannedGitHubActionKind
    public var title: String
    public var repoFullName: String
    public var repoName: String?
    public var repoDescription: String?
    public var issueNumber: Int?
    public var issueTitle: String?
    public var labels: [String]
    public var body: String
    public var suggestedAction: String

    public init(
        kind: PlannedGitHubActionKind,
        title: String,
        repoFullName: String,
        repoName: String? = nil,
        repoDescription: String? = nil,
        issueNumber: Int? = nil,
        issueTitle: String? = nil,
        labels: [String] = [],
        body: String,
        suggestedAction: String
    ) {
        self.kind = kind
        self.title = title
        self.repoFullName = repoFullName
        self.repoName = repoName
        self.repoDescription = repoDescription
        self.issueNumber = issueNumber
        self.issueTitle = issueTitle
        self.labels = labels
        self.body = body
        self.suggestedAction = suggestedAction
    }
}

public struct ShadowRepoActionContext: Equatable {
    public var name: String
    public var fullName: String
    public var agentState: String

    public init(name: String, fullName: String, agentState: String) {
        self.name = name
        self.fullName = fullName
        self.agentState = agentState
    }
}

public struct ShadowIssueActionContext: Equatable {
    public var number: Int
    public var title: String

    public init(number: Int, title: String) {
        self.number = number
        self.title = title
    }
}

public enum ShadowGitHubActionPlanner {
    public static func plan(
        command: String,
        repo: ShadowRepoActionContext?,
        issue: ShadowIssueActionContext?,
        allowCreateRepoWithoutSelection: Bool
    ) -> ShadowGitHubActionPlan? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let repo else {
            guard allowCreateRepoWithoutSelection, let repoName = extractRepoName(from: trimmed) else {
                return nil
            }
            return ShadowGitHubActionPlan(
                kind: .createRepo,
                title: "Create private repo: \(repoName)",
                repoFullName: repoName,
                repoName: repoName,
                repoDescription: descriptionText(from: trimmed),
                body: trimmed.isEmpty ? "Create a new repo/project card." : trimmed,
                suggestedAction: "Create a private GitHub repo/project named \(repoName)."
            )
        }

        if let issue {
            let body = buildIssueCommentBody(
                command: trimmed,
                repo: repo,
                issue: issue
            )
            return ShadowGitHubActionPlan(
                kind: .issueComment,
                title: "Add comment to \(repo.name)#\(issue.number)",
                repoFullName: repo.fullName,
                issueNumber: issue.number,
                body: body,
                suggestedAction: "Add a confirmation-gated issue comment to \(repo.name)#\(issue.number)."
            )
        }

        let title = trimmed.split(separator: "\n").first.map(String.init) ?? "Smart Shadow follow-up"
        let body = buildIssueBody(command: trimmed, repo: repo)
        return ShadowGitHubActionPlan(
            kind: .createIssue,
            title: "Create issue in \(repo.name): \(title)",
            repoFullName: repo.fullName,
            issueTitle: "新任务",
            labels: ["smart-shadow", "shadow:inbox"],
            body: body,
            suggestedAction: "Create a confirmation-gated issue in \(repo.name)."
        )
    }

    public static func extractRepoName(from command: String) -> String? {
        let firstLine = command
            .split(separator: "\n", maxSplits: 1)
            .first
            .map(String.init)?
            .replacingOccurrences(of: "Create a new repo/project for", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Create a new repo for", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Create repo", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstLine, !firstLine.isEmpty else { return nil }
        let allowed = firstLine.lowercased().map { character -> Character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
        }
        let collapsed = String(allowed)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(80))
    }

    public static func descriptionText(from command: String) -> String? {
        let lines = command
            .split(separator: "\n")
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let description = lines.joined(separator: "\n")
        return description.isEmpty ? nil : description
    }

    private static func buildIssueBody(command: String, repo: ShadowRepoActionContext) -> String {
        let finalText = command.isEmpty ? "Review this repo and define the next concrete action." : command
        let firstLine = finalText.split(separator: "\n").first.map(String.init) ?? finalText
        return """
        ## Background

        \(finalText)

        ## Goal

        \(firstLine)

        ## Scope

        ### In scope

        - Execute the user-confirmed Smart Shadow task for `\(repo.fullName)`.
        - Report meaningful progress in GitHub issue comments.

        ### Out of scope

        - Unconfirmed follow-up changes.
        - Work outside `\(repo.fullName)` unless Shadow asks for confirmation.

        ## Acceptance Criteria

        - Shadow can execute from this final text task.
        - Progress, blockers, PR links, and completion summary are recorded on this issue.
        - The user can review the result from the Smart Shadow app.

        <details>
        <summary>Smart Shadow metadata</summary>

        - Source: Smart Shadow
        - Input: voice
        - Audio: not_uploaded
        - Write identity: user GitHub account
        - Execution identity: shadow
        - Shadow status: inbox
        - Repo: \(repo.fullName)
        - Agent state: \(repo.agentState)

        </details>

        <!-- smart-shadow
        source: smart-shadow
        input: voice
        audio: not_uploaded
        created_by: user
        shadow_status: inbox
        -->
        """
    }

    private static func buildIssueCommentBody(
        command: String,
        repo: ShadowRepoActionContext,
        issue: ShadowIssueActionContext
    ) -> String {
        let finalText = command.isEmpty ? "Review this issue and confirm the next concrete action." : command
        return """
        ## Smart Shadow Follow-up

        \(finalText)

        <details>
        <summary>Smart Shadow metadata</summary>

        - Source: Smart Shadow
        - Input: voice
        - Audio: not_uploaded
        - Write identity: user GitHub account
        - Execution identity: shadow
        - Comment type: user_context
        - Repo: \(repo.fullName)
        - Issue: #\(issue.number) \(issue.title)
        - Agent state: \(repo.agentState)

        </details>

        <!-- smart-shadow
        source: smart-shadow
        input: voice
        audio: not_uploaded
        comment_type: user_context
        -->
        """
    }
}
