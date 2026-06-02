import Foundation

public enum ServiceSummary: String, Sendable {
    case running
    case attention
    case stopped
    case unknown

    public var title: String {
        switch self {
        case .running: "运行中"
        case .attention: "需要注意"
        case .stopped: "已停止"
        case .unknown: "未知"
        }
    }

    public var systemImage: String {
        switch self {
        case .running: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .stopped: "pause.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

public struct ServiceStatus: Decodable, Sendable {
    public let status: String
    public let overallState: String
    public let pollSeconds: Int
    public let launchd: LaunchdStatus
    public let lastRunReport: RunReport?
    public let attention: [AttentionItem]
    public let eventKit: EventKitStatus
    public let sourceDoctor: SourceDoctor
    public let logs: LogPaths

    public var summary: ServiceSummary {
        if !launchd.loaded {
            return .stopped
        }
        if overallState == "attention_required" || !attention.isEmpty {
            return .attention
        }
        if lastRunReport?.fresh == false {
            return .attention
        }
        return status == "ok" ? .running : .unknown
    }

    public init(jsonData: Data) throws {
        self = try JSONDecoder.smartShadow.decode(ServiceStatus.self, from: jsonData)
    }

    enum CodingKeys: String, CodingKey {
        case status
        case overallState = "overall_state"
        case pollSeconds = "poll_seconds"
        case launchd
        case lastRunReport = "last_run_report"
        case attention
        case eventKit = "eventkit"
        case sourceDoctor = "source_doctor"
        case logs
    }
}

public struct LaunchdStatus: Decodable, Sendable {
    public let loaded: Bool
    public let detail: String
    public let target: String?
    public let launchctlStatus: Int?

    enum CodingKeys: String, CodingKey {
        case loaded
        case detail
        case target
        case launchctlStatus = "launchctl_status"
    }
}

public struct RunReport: Decodable, Sendable {
    public let timestamp: String?
    public let processedCount: Int?
    public let errorCount: Int?
    public let fresh: Bool?
    public let ageSeconds: Int?
    public let staleAfterSeconds: Int?
    public let path: String?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case processedCount = "processed_count"
        case errorCount = "error_count"
        case fresh
        case ageSeconds = "age_seconds"
        case staleAfterSeconds = "stale_after_seconds"
        case path
    }
}

public struct AttentionItem: Decodable, Identifiable, Sendable {
    public var id: String { "\(code)-\(source ?? suggestedCommand ?? message)" }

    public let code: String
    public let message: String
    public let source: String?
    public let suggestedCommand: String?
    public let blockers: [String]?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case source
        case suggestedCommand = "suggested_command"
        case blockers
    }
}

public struct EventKitStatus: Decodable, Sendable {
    public let calendar: String?
    public let reminders: String?
    public let mode: String?
}

public struct SourceDoctor: Decodable, Sendable {
    public let sources: [SourceStatus]
}

public struct SourceStatus: Decodable, Identifiable, Sendable {
    public var id: String { name }

    public let name: String
    public let enabled: Bool
    public let readyToEnable: Bool
    public let acceptanceStatus: String?
    public let blockers: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case enabled
        case readyToEnable = "ready_to_enable"
        case acceptanceStatus = "acceptance_status"
        case blockers
    }
}

public struct LogPaths: Decodable, Sendable {
    public let audit: String?
    public let launchdStdout: String?
    public let launchdStderr: String?

    enum CodingKeys: String, CodingKey {
        case audit
        case launchdStdout = "launchd_stdout"
        case launchdStderr = "launchd_stderr"
    }
}

