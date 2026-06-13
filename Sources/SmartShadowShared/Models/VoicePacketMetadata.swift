import Foundation

public enum VoicePacketSource: String, Codable, Equatable {
    case iOS = "ios"
    case macOS = "macos"

    public var platform: String {
        switch self {
        case .iOS: "iOS"
        case .macOS: "macOS"
        }
    }
}

public struct VoicePacketMetadata: Codable, Equatable {
    public var packetID: String
    public var createdAt: String
    public var user: String
    public var source: String
    public var app: String
    public var domain: String
    public var audioFile: String
    public var status: String
    public var target: VoicePacketTarget?
    public var client: VoicePacketClient

    public enum CodingKeys: String, CodingKey {
        case packetID = "packet_id"
        case createdAt = "created_at"
        case user
        case source
        case app
        case domain
        case audioFile = "audio_file"
        case status
        case target
        case client
    }

    public static func make(
        packetID: String,
        now: Date = Date(),
        user: String,
        source: VoicePacketSource,
        target: VoicePacketTarget? = nil,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> VoicePacketMetadata {
        VoicePacketMetadata(
            packetID: packetID,
            createdAt: ISO8601DateFormatter.localInternetDateTimeString(from: now, timeZone: calendar.timeZone),
            user: user,
            source: source.rawValue,
            app: "SmartShadow",
            domain: "smart-shadow.bozhi.ai",
            audioFile: "audio.m4a",
            status: "pending",
            target: target,
            client: VoicePacketClient(
                platform: source.platform,
                timezone: calendar.timeZone.identifier,
                locale: locale.identifier
            )
        )
    }
}

public struct VoicePacketTarget: Codable, Equatable {
    public var type: String
    public var repo: String
    public var issueNumber: Int

    public init(type: String, repo: String, issueNumber: Int) {
        self.type = type
        self.repo = repo
        self.issueNumber = issueNumber
    }

    public enum CodingKeys: String, CodingKey {
        case type
        case repo
        case issueNumber = "issue_number"
    }
}

public struct VoicePacketClient: Codable, Equatable {
    public var platform: String
    public var timezone: String
    public var locale: String

    public init(platform: String, timezone: String, locale: String) {
        self.platform = platform
        self.timezone = timezone
        self.locale = locale
    }
}

public struct VoicePacketDescriptor: Equatable {
    public var packetID: String
    public var inboxPath: String

    public init(packetID: String, inboxPath: String = "inbox/pending") {
        self.packetID = packetID
        self.inboxPath = inboxPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public var pendingDirectory: String {
        "\(inboxPath)/\(datePath)/\(packetID)"
    }

    public var audioPath: String {
        "\(pendingDirectory)/audio.m4a"
    }

    public var metadataPath: String {
        "\(pendingDirectory)/meta.json"
    }

    private var datePath: String {
        let parts = packetID.split(separator: "_")
        let date = parts.count >= 2 ? parts[1] : "19700101"
        let year = date.prefix(4)
        let month = date.dropFirst(4).prefix(2)
        let day = date.dropFirst(6).prefix(2)
        return "\(year)-\(month)-\(day)"
    }

    public static func makePacketID(now: Date = Date(), calendar: Calendar = .current, suffix: String? = nil) -> String {
        let components = calendar.dateComponents(in: calendar.timeZone, from: now)
        let suffix = suffix ?? randomHexSuffix()
        return String(
            format: "voice_%04d%02d%02d_%02d%02d%02d_%@",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0,
            suffix
        )
    }

    private static func randomHexSuffix() -> String {
        String(format: "%04x", Int.random(in: 0...0xffff))
    }
}

public struct VoicePacketUpload: Equatable {
    public var packetID: String
    public var audioURL: URL
    public var user: String
    public var source: VoicePacketSource

    public init(packetID: String, audioURL: URL, user: String, source: VoicePacketSource) {
        self.packetID = packetID
        self.audioURL = audioURL
        self.user = user
        self.source = source
    }
}

public struct VoicePacketDelivery: Codable, Equatable, Identifiable {
    public var packetID: String
    public var repositoryPath: String
    public var uploadedAt: String
    public var status: DeliveryStatus
    public var errorMessage: String?

    public init(packetID: String, repositoryPath: String, uploadedAt: String, status: DeliveryStatus, errorMessage: String?) {
        self.packetID = packetID
        self.repositoryPath = repositoryPath
        self.uploadedAt = uploadedAt
        self.status = status
        self.errorMessage = errorMessage
    }

    public var id: String { packetID }

    public var displayTime: String {
        String(uploadedAt.dropFirst(11).prefix(5))
    }
}

public enum DeliveryStatus: String, Codable, Equatable {
    case uploaded
    case failed

    public var title: String { rawValue }
}

public extension Calendar {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}

public extension ISO8601DateFormatter {
    static func localInternetDateTimeString(from date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

public extension JSONEncoder {
    static var smartShadowPretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
