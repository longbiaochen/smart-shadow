import Foundation

public enum ShadowIssueStatus: String, CaseIterable, Equatable, Sendable {
    case inbox = "shadow:inbox"
    case triaging = "shadow:triaging"
    case planned = "shadow:planned"
    case running = "shadow:running"
    case waitingUser = "shadow:waiting-user"
    case prOpened = "shadow:pr-opened"
    case done = "shadow:done"
    case failed = "shadow:failed"
}

public struct ShadowIssueStateTransition: Equatable, Sendable {
    public var from: ShadowIssueStatus?
    public var to: ShadowIssueStatus
    public var labels: [String]
    public var comment: String?

    public init(from: ShadowIssueStatus?, to: ShadowIssueStatus, labels: [String], comment: String?) {
        self.from = from
        self.to = to
        self.labels = labels
        self.comment = comment
    }
}

public enum IssueStateMachine {
    public static func currentStatus(labels: [String]) -> ShadowIssueStatus? {
        let normalized = Set(labels.map { $0.lowercased() })
        return ShadowIssueStatus.allCases.first { normalized.contains($0.rawValue) }
    }

    public static func transition(
        labels: [String],
        to target: ShadowIssueStatus,
        comment: String? = nil
    ) -> ShadowIssueStateTransition {
        let existing = currentStatus(labels: labels)
        var nextLabels = labels.filter { label in
            !ShadowIssueStatus.allCases.map(\.rawValue).contains(label.lowercased())
        }
        if !nextLabels.contains(where: { $0.lowercased() == "smart-shadow" }) {
            nextLabels.append("smart-shadow")
        }
        nextLabels.append(target.rawValue)
        return ShadowIssueStateTransition(
            from: existing,
            to: target,
            labels: nextLabels,
            comment: comment
        )
    }
}
