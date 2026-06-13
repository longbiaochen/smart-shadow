import Foundation

public struct SmartShadowIssueEnvelope: Equatable, Sendable {
    public var title: String
    public var labels: [String]
    public var body: String

    public init(title: String, labels: [String], body: String) {
        self.title = title
        self.labels = labels
        self.body = body
    }
}

public struct SmartShadowIssueContext: Equatable, Sendable {
    public var source: String?
    public var input: String?
    public var audio: String?
    public var createdBy: String?
    public var shadowStatus: String?
    public var commentType: String?
    public var isSmartShadowTask: Bool
    public var isFinalTextTask: Bool

    public init(
        source: String?,
        input: String?,
        audio: String?,
        createdBy: String?,
        shadowStatus: String?,
        commentType: String?,
        isSmartShadowTask: Bool,
        isFinalTextTask: Bool
    ) {
        self.source = source
        self.input = input
        self.audio = audio
        self.createdBy = createdBy
        self.shadowStatus = shadowStatus
        self.commentType = commentType
        self.isSmartShadowTask = isSmartShadowTask
        self.isFinalTextTask = isFinalTextTask
    }
}

public enum SmartShadowIssueParser {
    public static func parse(_ issue: SmartShadowIssueEnvelope) -> SmartShadowIssueContext? {
        let metadata = parseMetadataBlock(issue.body)
        let normalizedLabels = Set(issue.labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let isSmartShadowTask = normalizedLabels.contains("smart-shadow") || metadata["source"] == "smart-shadow" || metadata["source"] == "ios" || metadata["source"] == "macos"

        guard isSmartShadowTask else { return nil }

        let audio = metadata["audio"]
        let input = metadata["input"]
        let hasLegacyAudio = bodyLooksLikeLegacyAudioPayload(issue.body)
        let isFinalTextTask = audio == "not_uploaded" && !hasLegacyAudio

        return SmartShadowIssueContext(
            source: metadata["source"],
            input: input,
            audio: audio,
            createdBy: metadata["created_by"],
            shadowStatus: metadata["shadow_status"],
            commentType: metadata["comment_type"],
            isSmartShadowTask: isSmartShadowTask,
            isFinalTextTask: isFinalTextTask
        )
    }

    public static func parseMetadataBlock(_ body: String) -> [String: String] {
        guard let block = extractHTMLMetadataBlock(from: body) else { return [:] }
        var metadata: [String: String] = [:]
        for rawLine in block.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !key.isEmpty, !value.isEmpty {
                metadata[key] = value
            }
        }
        return metadata
    }

    private static func extractHTMLMetadataBlock(from body: String) -> String? {
        guard let startRange = body.range(of: "<!-- smart-shadow", options: [.caseInsensitive]) else {
            return nil
        }
        let contentStart = startRange.upperBound
        guard let endRange = body[contentStart...].range(of: "-->") else {
            return nil
        }
        return String(body[contentStart..<endRange.lowerBound])
    }

    private static func bodyLooksLikeLegacyAudioPayload(_ body: String) -> Bool {
        let lowered = body.lowercased()
        return lowered.contains("audio.m4a")
            || lowered.contains("audio_file")
            || lowered.contains("audio_path")
            || lowered.contains("raw transcript")
            || lowered.contains("githubinboxuploader")
    }
}
