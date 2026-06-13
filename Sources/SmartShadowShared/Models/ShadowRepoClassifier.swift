import Foundation

public enum ShadowLifeArea: String, Sendable, CaseIterable, Equatable {
    case work = "WORK"
    case money = "MONEY"
    case health = "HEALTH"
    case network = "NETWORK"
}

public enum ShadowRepoBucket: String, Sendable, CaseIterable, Equatable {
    case important = "IMPORTANT"
    case urgent = "URGENT"
    case doing = "DOING"
    case todo = "TODO"
}

public struct ShadowRepoClassificationInput: Sendable, Equatable {
    public var name: String
    public var description: String?
    public var topics: [String]
    public var openIssueCount: Int

    public init(name: String, description: String?, topics: [String], openIssueCount: Int) {
        self.name = name
        self.description = description
        self.topics = topics
        self.openIssueCount = openIssueCount
    }
}

public struct ShadowRepoClassification: Sendable, Equatable {
    public var area: ShadowLifeArea
    public var bucket: ShadowRepoBucket

    public init(area: ShadowLifeArea, bucket: ShadowRepoBucket) {
        self.area = area
        self.bucket = bucket
    }
}

public enum ShadowRepoClassifier {
    public static func classify(_ input: ShadowRepoClassificationInput) -> ShadowRepoClassification {
        let text = normalizedText(input)
        return ShadowRepoClassification(
            area: area(for: text),
            bucket: bucket(for: text, openIssueCount: input.openIssueCount)
        )
    }

    private static func area(for text: String) -> ShadowLifeArea {
        if containsAny(text, ["money", "finance", "trading", "sales", "revenue", "quant", "invoice", "pricing", "contract"]) {
            return .money
        }
        if containsAny(text, ["health", "sleep", "mind", "fitness", "medical", "diet", "routine", "therapy"]) {
            return .health
        }
        if containsAny(text, ["network", "relationship", "comms", "communication", "crm", "people", "family", "friend"]) {
            return .network
        }
        return .work
    }

    private static func bucket(for text: String, openIssueCount: Int) -> ShadowRepoBucket {
        if containsAny(text, ["urgent", "hotfix", "blocker", "blocked", "deadline", "fire", "today"]) {
            return .urgent
        }
        if containsAny(text, ["important", "strategy", "core", "life-os", "system", "platform", "security", "risk"]) || openIssueCount >= 8 {
            return .important
        }
        if containsAny(text, ["doing", "active", "in-progress", "progress", "current", "now"]) || openIssueCount > 0 {
            return .doing
        }
        return .todo
    }

    private static func normalizedText(_ input: ShadowRepoClassificationInput) -> String {
        "\(input.name) \(input.description ?? "") \(input.topics.joined(separator: " "))"
            .lowercased()
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
