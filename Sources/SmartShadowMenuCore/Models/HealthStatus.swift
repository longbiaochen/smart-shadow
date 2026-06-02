import Foundation

public struct HealthStatus: Decodable, Sendable {
    public let status: String
    public let runtimeRoot: String?
    public let counts: HealthCounts
    public let recent: [RecentItem]

    public init(jsonData: Data) throws {
        self = try JSONDecoder.smartShadow.decode(HealthStatus.self, from: jsonData)
    }

    enum CodingKeys: String, CodingKey {
        case status
        case runtimeRoot = "runtime_root"
        case counts
        case recent
    }
}

public struct HealthCounts: Decodable, Sendable {
    public let signals: Int?
    public let decisions: Int?
    public let actions: Int?
    public let pendingActions: Int?
    public let projections: Int?

    enum CodingKeys: String, CodingKey {
        case signals
        case decisions
        case actions
        case pendingActions = "pending_actions"
        case projections
    }
}

public struct RecentItem: Decodable, Identifiable, Sendable {
    public var id: String { "\(signalID ?? -1)-\(title)" }

    public let signalID: Int?
    public let title: String
    public let domain: String?
    public let risk: String?
    public let status: String?
    public let decisionAction: String?

    enum CodingKeys: String, CodingKey {
        case signalID = "signal_id"
        case title
        case domain
        case risk
        case status
        case decisionAction = "decision_action"
    }
}

