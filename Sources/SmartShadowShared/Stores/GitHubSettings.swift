import Foundation
import Security

public struct GitHubSettings: Codable, Equatable, Sendable {
    public var owner: String
    public var repo: String
    public var inboxPath: String
    public var token: String

    private enum CodingKeys: String, CodingKey {
        case owner
        case repo
        case inboxPath
    }

    public init(owner: String, repo: String, inboxPath: String = "inbox/pending", token: String = "") {
        self.owner = owner
        self.repo = repo
        self.inboxPath = inboxPath
        self.token = token
    }

    public static let defaults = GitHubSettings(
        owner: "longbiaochen",
        repo: "life-os",
        inboxPath: "inbox/pending",
        token: ""
    )

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        owner = try container.decode(String.self, forKey: .owner)
        repo = try container.decode(String.self, forKey: .repo)
        inboxPath = try container.decodeIfPresent(String.self, forKey: .inboxPath) ?? "inbox/pending"
        token = ""
    }

    public static func load(defaults: UserDefaults = .standard) -> GitHubSettings {
        let token = KeychainTokenStore.loadToken() ?? ""
        guard let data = defaults.data(forKey: "githubSettings") else {
            var value = Self.defaults
            value.token = token
            return value
        }
        var value = (try? JSONDecoder().decode(GitHubSettings.self, from: data)) ?? Self.defaults
        value.token = token
        return value
    }

    public func save(defaults: UserDefaults = .standard) {
        var value = self
        value.token = ""
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: "githubSettings")
        KeychainTokenStore.saveToken(token)
    }
}

public enum KeychainTokenStore {
    private static let service = "me.longbiaochen.smart-shadow.github-token"
    private static let account = "GITHUB_TOKEN"

    public static func loadToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func saveToken(_ token: String) {
        SecItemDelete(baseQuery() as CFDictionary)
        guard !token.isEmpty, let data = token.data(using: .utf8) else { return }
        var item = baseQuery()
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    public static func deleteToken() {
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

public enum GitHubOAuthConfig {
    private static let userDefaultsKey = "githubOAuthClientID"

    public static func loadClientID(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> String {
        if let saved = defaults.string(forKey: userDefaultsKey), !saved.isEmpty {
            return saved
        }
        if let bundled = bundle.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String,
           !bundled.isEmpty,
           !bundled.hasPrefix("$(") {
            return bundled
        }
        return ""
    }

    public static func saveClientID(_ value: String, defaults: UserDefaults = .standard) {
        defaults.set(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: userDefaultsKey)
    }
}
