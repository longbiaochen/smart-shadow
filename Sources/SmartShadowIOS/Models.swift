import Foundation
import Security
import SmartShadowGitHubAPI
import SmartShadowShared
import SwiftUI

struct GitHubSettings: Codable, Equatable {
    var owner: String
    var repo: String
    var token: String = ""

    private enum CodingKeys: String, CodingKey {
        case owner
        case repo
    }

    static let defaults = GitHubSettings(
        owner: "longbiaochen",
        repo: "life-os",
        token: ""
    )

    static func load() -> GitHubSettings {
        let token = KeychainTokenStore.loadToken() ?? ""
        guard let data = UserDefaults.standard.data(forKey: "githubSettings") else {
            var value = defaults
            value.token = token
            return value
        }
        var value = (try? JSONDecoder().decode(GitHubSettings.self, from: data)) ?? defaults
        value.token = token
        return value
    }

    func save() {
        var value = self
        value.token = ""
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: "githubSettings")
        KeychainTokenStore.saveToken(token)
    }
}

enum KeychainTokenStore {
    private static let service = "me.longbiaochen.smart-shadow.github-token"
    private static let account = "GITHUB_TOKEN"

    static func loadToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveToken(_ token: String) {
        SecItemDelete(baseQuery() as CFDictionary)
        guard !token.isEmpty, let data = token.data(using: .utf8) else { return }
        var item = baseQuery()
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func deleteToken() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct VoicePacketMetadata: Codable, Equatable {
    var packetID: String
    var createdAt: String
    var user: String
    var source: String
    var app: String
    var domain: String
    var mode: VoicePacketMode
    var target: VoicePacketTarget?
    var audioFile: String
    var status: String
    var client: VoicePacketClient

    enum CodingKeys: String, CodingKey {
        case packetID = "packet_id"
        case createdAt = "created_at"
        case user
        case source
        case app
        case domain
        case mode
        case target
        case audioFile = "audio_file"
        case status
        case client
    }
}

enum VoicePacketMode: String, Codable, Equatable {
    case newTask = "new_task"
    case followUp = "follow_up"
}

struct VoicePacketTarget: Codable, Equatable {
    var type: String
    var repo: String
    var issueNumber: Int

    enum CodingKeys: String, CodingKey {
        case type
        case repo
        case issueNumber = "issue_number"
    }
}

struct VoicePacketClient: Codable, Equatable {
    var platform: String
    var timezone: String
    var locale: String
}

struct FollowUpContext: Codable, Equatable {
    var repo: String
    var issueNumber: Int

    static func parse(url: URL) -> FollowUpContext? {
        guard url.scheme == "https",
              url.host == "smart-shadow.bozhi.ai",
              url.path == "/followup",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let items = components.queryItems ?? []
        guard let repo = items.first(where: { $0.name == "repo" })?.value,
              repo.contains("/"),
              let issueValue = items.first(where: { $0.name == "issue" })?.value,
              let issueNumber = Int(issueValue),
              issueNumber > 0 else {
            return nil
        }
        return FollowUpContext(repo: repo, issueNumber: issueNumber)
    }
}

struct VoicePacketDelivery: Codable, Equatable, Identifiable {
    var packetID: String
    var repositoryPath: String
    var uploadedAt: String
    var status: DeliveryStatus
    var errorMessage: String?

    var id: String { packetID }

    var displayTime: String {
        String(uploadedAt.dropFirst(11).prefix(5))
    }
}

struct VoicePacketUpload: Equatable {
    var packetID: String
    var audioURL: URL
    var user: String
    var context: FollowUpContext?
    var audioUploaded: Bool
}

enum DeliveryStatus: String, Codable, Equatable {
    case uploaded
    case failed

    var title: String {
        switch self {
        case .uploaded: "uploaded"
        case .failed: "failed"
        }
    }
}

enum VoiceTaskFactory {
    static func makePacketID(now: Date = Date(), calendar: Calendar = .current, suffix: String? = nil) -> String {
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

    static func pendingDirectory(packetID: String) -> String {
        let parts = packetID.split(separator: "_")
        let date = parts.count >= 2 ? parts[1] : "19700101"
        let year = date.prefix(4)
        let month = date.dropFirst(4).prefix(2)
        let day = date.dropFirst(6).prefix(2)
        return "inbox/pending/\(year)-\(month)-\(day)/\(packetID)"
    }

    static func audioPath(packetID: String) -> String {
        "\(pendingDirectory(packetID: packetID))/audio.m4a"
    }

    static func metadataPath(packetID: String) -> String {
        "\(pendingDirectory(packetID: packetID))/meta.json"
    }

    static func metadata(
        packetID: String,
        now: Date = Date(),
        user: String = "Longbiao",
        context: FollowUpContext? = nil,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> VoicePacketMetadata {
        VoicePacketMetadata(
            packetID: packetID,
            createdAt: ISO8601DateFormatter.localInternetDateTimeString(from: now),
            user: user,
            source: "ios",
            app: "SmartShadow",
            domain: "smart-shadow.bozhi.ai",
            mode: context == nil ? .newTask : .followUp,
            target: context.map { VoicePacketTarget(type: "github_issue", repo: $0.repo, issueNumber: $0.issueNumber) },
            audioFile: "audio.m4a",
            status: "pending",
            client: VoicePacketClient(
                platform: "iOS",
                timezone: calendar.timeZone.identifier,
                locale: locale.identifier
            )
        )
    }

    static func upload(audioURL: URL, user: String = "Longbiao", context: FollowUpContext? = nil) -> VoicePacketUpload {
        VoicePacketUpload(
            packetID: makePacketID(),
            audioURL: audioURL,
            user: user,
            context: context,
            audioUploaded: false
        )
    }

    private static func randomHexSuffix() -> String {
        String(format: "%04x", Int.random(in: 0...0xffff))
    }
}

extension Calendar {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}

extension ISO8601DateFormatter {
    static func localInternetDateTimeString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

enum GitHubOAuthConfig {
    private static let userDefaultsKey = "githubOAuthClientID"

    static func loadClientID() -> String {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey), !saved.isEmpty {
            return saved
        }
        if let bundled = Bundle.main.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String,
           !bundled.isEmpty,
           !bundled.hasPrefix("$(") {
            return bundled
        }
        return ""
    }

    static func saveClientID(_ value: String) {
        UserDefaults.standard.set(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: userDefaultsKey)
    }
}

enum LifeArea: String, CaseIterable, Identifiable {
    case work = "WORK"
    case money = "MONEY"
    case health = "HEALTH"
    case network = "NETWORK"
    case mine = "我的"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .work: "briefcase"
        case .money: "chart.line.uptrend.xyaxis"
        case .health: "heart.text.square"
        case .network: "person.2.wave.2"
        case .mine: "person.crop.circle"
        }
    }

    init(classified area: ShadowLifeArea) {
        switch area {
        case .work:
            self = .work
        case .money:
            self = .money
        case .health:
            self = .health
        case .network:
            self = .network
        }
    }
}

enum RepoBucket: String, CaseIterable, Identifiable {
    case important = "IMPORTANT"
    case urgent = "URGENT"
    case doing = "DOING"
    case todo = "TODO"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .important: .cyan
        case .urgent: .orange
        case .doing: .green
        case .todo: .secondary
        }
    }

    init(classified bucket: ShadowRepoBucket) {
        switch bucket {
        case .important:
            self = .important
        case .urgent:
            self = .urgent
        case .doing:
            self = .doing
        case .todo:
            self = .todo
        }
    }
}

enum VoiceInteractionState: Equatable {
    case idle
    case listening
    case uploading
    case responding(String)
    case uploaded(VoicePacketDelivery)
    case failed(String)

    var statusText: String {
        switch self {
        case .idle: "按住，说给影子听"
        case .listening: "松开发送"
        case .uploading: "正在送达影子..."
        case let .responding(text): text
        case .uploaded: "影子已收到"
        case .failed: "上传失败 点击重试"
        }
    }

    var orbScale: CGFloat {
        switch self {
        case .idle: 1.0
        case .listening: 1.18
        case .uploading: 0.86
        case .responding: 1.12
        case .uploaded: 1.08
        case .failed: 0.94
        }
    }

    var pulseOpacity: Double {
        switch self {
        case .idle: 0.22
        case .listening: 0.46
        case .uploading: 0.16
        case .responding: 0.36
        case .uploaded: 0.30
        case .failed: 0.20
        }
    }
}

struct ShadowRepo: Identifiable, Equatable {
    var id: Int
    var name: String
    var fullName: String
    var description: String
    var nextAction: String
    var openIssueCount: Int
    var openPRCount: Int
    var labels: [String]
    var status: String
    var updatedAt: Date
    var reviewDate: Date
    var agentState: String
    var area: LifeArea
    var bucket: RepoBucket
}

struct ShadowIssue: Identifiable, Equatable {
    var id: Int
    var number: Int
    var title: String
    var status: String
    var labels: [String]
    var assignee: String
    var updatedAt: Date
    var commentCount: Int
    var linkedPRStatus: String
    var needsDecision: Bool
    var summary: String
    var timeline: [String]
    var comments: [String]
}

struct GitHubClient {
    var token: String
    var session: URLSession = .shared

    private var api: GitHubAPIClient {
        GitHubAPIClient(token: token, session: session, userAgent: "smart-shadow-ios")
    }

    func fetchRepositories() async throws -> [ShadowRepo] {
        let repos = try await api.fetchRepositories()
        return repos.enumerated().map { index, repo in
            let classification = ShadowRepoClassifier.classify(
                ShadowRepoClassificationInput(
                    name: repo.name,
                    description: repo.description,
                    topics: repo.topics ?? [],
                    openIssueCount: repo.openIssuesCount
                )
            )
            return ShadowRepo(
                id: repo.id,
                name: repo.name,
                fullName: repo.fullName,
                description: repo.description?.isEmpty == false ? repo.description! : "No description yet.",
                nextAction: Self.nextAction(for: repo),
                openIssueCount: repo.openIssuesCount,
                openPRCount: 0,
                labels: Array((repo.topics ?? []).prefix(4)),
                status: Self.status(for: repo),
                updatedAt: repo.updatedAt,
                reviewDate: Calendar.current.date(byAdding: .day, value: index % 5 + 1, to: Date()) ?? Date(),
                agentState: index % 3 == 0 ? "watching" : "idle",
                area: LifeArea(classified: classification.area),
                bucket: RepoBucket(classified: classification.bucket)
            )
        }
    }

    func fetchIssues(repoFullName: String) async throws -> [ShadowIssue] {
        let issues = try await api.fetchIssues(repoFullName: repoFullName)
        var mappedIssues: [ShadowIssue] = []
        for issue in issues.filter({ !$0.isPullRequest }) {
            let comments = await commentRows(for: issue, repoFullName: repoFullName)
            mappedIssues.append(
                ShadowIssue(
                    id: issue.id,
                    number: issue.number,
                    title: issue.title,
                    status: issue.state,
                    labels: issue.labels.map(\.name),
                    assignee: issue.assignee?.login ?? "unassigned",
                    updatedAt: issue.updatedAt,
                    commentCount: issue.comments,
                    linkedPRStatus: "none",
                    needsDecision: issue.labels.contains { $0.name.lowercased().contains("decision") || $0.name.lowercased().contains("review") },
                    summary: issue.body?.split(separator: "\n").prefix(2).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "No summary yet.",
                    timeline: ["opened", "updated \(Self.shortDate(issue.updatedAt))"],
                    comments: comments
                )
            )
        }
        return mappedIssues
    }

    private func commentRows(for issue: GitHubAPIIssue, repoFullName: String) async -> [String] {
        guard issue.comments > 0 else {
            return ["No comments yet."]
        }
        do {
            let comments = try await api.fetchIssueComments(repoFullName: repoFullName, issueNumber: issue.number)
            let rows = comments.prefix(3).compactMap(Self.commentRow)
            return rows.isEmpty ? ["\(issue.comments) GitHub comments"] : rows
        } catch {
            return ["\(issue.comments) GitHub comments"]
        }
    }

    private static func commentRow(_ comment: GitHubAPIIssueComment) -> String? {
        let body = comment.body?
            .split(separator: "\n")
            .prefix(2)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let body, !body.isEmpty else {
            return nil
        }
        return "@\(comment.user?.login ?? "unknown"): \(body)"
    }

    func fetchPullCount(repoFullName: String) async throws -> Int {
        try await api.fetchPullCount(repoFullName: repoFullName)
    }

    func createIssueComment(repoFullName: String, issueNumber: Int, body: String) async throws {
        try await api.createIssueComment(repoFullName: repoFullName, issueNumber: issueNumber, body: body)
    }

    func createIssue(repoFullName: String, title: String, body: String, labels: [String]) async throws {
        try await api.createIssue(repoFullName: repoFullName, title: title, body: body, labels: labels)
    }

    func createRepository(name: String, description: String?) async throws {
        try await api.createRepository(name: name, description: description)
    }

    private static func nextAction(for repo: GitHubAPIRepository) -> String {
        repo.openIssuesCount == 0 ? "Review repo status and define next issue." : "Triage open issues and pick one user-visible move."
    }

    private static func status(for repo: GitHubAPIRepository) -> String {
        repo.openIssuesCount == 0 ? "quiet" : "active"
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

extension GitHubClient: ShadowGitHubWriteClient {}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

@MainActor
final class ShadowSession: ObservableObject {
    @Published var settings: GitHubSettings
    @Published var oauthClientID: String
    @Published var userLogin: String?
    @Published var authStatus: String
    @Published var followUpContext: FollowUpContext?
    @Published var deliveryHistory: [VoicePacketDelivery]

    private let deliveryHistoryKey = "voicePacketDeliveryHistory"

    init() {
        let loadedSettings = GitHubSettings.load()
        settings = loadedSettings
        oauthClientID = GitHubOAuthConfig.loadClientID()
        authStatus = loadedSettings.token.isEmpty ? "GitHub 登录后继续" : "GitHub 已连接"
        deliveryHistory = Self.loadDeliveryHistory()

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-SmartShadowPreviewAuthenticated") {
            settings.token = "preview-token"
            userLogin = "Longbiao"
            authStatus = "GitHub 已连接：Longbiao"
        }
        #endif
    }

    var isAuthenticated: Bool {
        !settings.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveSettings() {
        settings.save()
        GitHubOAuthConfig.saveClientID(oauthClientID)
    }

    func applyOAuthToken(_ token: String, login: String?) {
        settings.token = token
        userLogin = login
        authStatus = login.map { "GitHub 已连接：\($0)" } ?? "GitHub 已连接"
        saveSettings()
    }

    func logout() {
        settings.token = ""
        userLogin = nil
        authStatus = "GitHub 登录后继续"
        followUpContext = nil
        deliveryHistory = []
        UserDefaults.standard.removeObject(forKey: deliveryHistoryKey)
        KeychainTokenStore.deleteToken()
    }

    func applyFollowUpURL(_ url: URL) {
        followUpContext = FollowUpContext.parse(url: url)
    }

    func consumeFollowUpContext() -> FollowUpContext? {
        let value = followUpContext
        followUpContext = nil
        return value
    }

    func recordDelivery(_ delivery: VoicePacketDelivery) {
        deliveryHistory.insert(delivery, at: 0)
        deliveryHistory = Array(deliveryHistory.prefix(10))
        if let data = try? JSONEncoder().encode(deliveryHistory) {
            UserDefaults.standard.set(data, forKey: deliveryHistoryKey)
        }
    }

    private static func loadDeliveryHistory() -> [VoicePacketDelivery] {
        guard let data = UserDefaults.standard.data(forKey: "voicePacketDeliveryHistory") else {
            return []
        }
        return (try? JSONDecoder().decode([VoicePacketDelivery].self, from: data)) ?? []
    }
}
