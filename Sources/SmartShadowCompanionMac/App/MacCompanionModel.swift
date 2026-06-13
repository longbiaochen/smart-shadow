import AppKit
import Combine
import ServiceManagement
import SmartShadowGitHubAPI
import SmartShadowShared

@MainActor
final class MacCompanionModel: ObservableObject {
    static let shared = MacCompanionModel()

    @Published var settings: GitHubSettings
    @Published var oauthClientID: String
    @Published var userLogin: String?
    @Published var authStatus: String
    @Published var state: VoiceEntryState = .idle
    @Published var errorMessage: String?
    @Published var deviceCode: GitHubOAuthDeviceCodeResponse?
    @Published var isLoggingIn = false
    @Published var deliveryHistory: [VoicePacketDelivery]
    @Published var launchAtLogin: Bool

    private let recorder = VoiceRecorderService()
    private let historyStore = DeliveryHistoryStore()
    private var activePacketID: String?
    private var activeAudioURL: URL?

    private init() {
        let loadedSettings = GitHubSettings.load()
        settings = loadedSettings
        oauthClientID = GitHubOAuthConfig.loadClientID()
        authStatus = loadedSettings.token.isEmpty ? "GitHub 登录后继续" : "GitHub 已连接"
        deliveryHistory = historyStore.deliveries
        launchAtLogin = SMAppService.mainApp.status == .enabled

        #if DEBUG
        if MacRuntimeMode.isPreviewAuthenticated {
            settings.token = "preview-token"
            userLogin = "bozhi-ai"
            authStatus = "GitHub 已连接：bozhi-ai"
        }
        #endif
    }

    var isAuthenticated: Bool {
        !settings.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var accountTitle: String {
        userLogin ?? (isAuthenticated ? "GitHub connected" : "Not logged in")
    }

    func saveSettings() {
        settings.save()
        GitHubOAuthConfig.saveClientID(oauthClientID)
    }

    func beginLogin() async {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        errorMessage = nil
        deviceCode = nil
        saveSettings()

        do {
            let service = GitHubOAuthService(userAgent: "smart-shadow-macos")
            let code = try await service.requestDeviceCode(clientID: oauthClientID)
            deviceCode = code
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code.userCode, forType: .string)
            NSWorkspace.shared.open(code.verificationURI)

            let token = try await service.pollForAccessToken(
                clientID: oauthClientID,
                deviceCode: code.deviceCode,
                interval: code.interval,
                expiresIn: code.expiresIn
            )
            let user = try await service.validateUser(token: token)
            applyOAuthToken(token, login: user.login)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoggingIn = false
    }

    func applyOAuthToken(_ token: String, login: String?) {
        settings.token = token
        userLogin = login
        authStatus = login.map { "GitHub 已连接：\($0)" } ?? "GitHub 已连接"
        saveSettings()
        NotificationCenter.default.post(name: .smartShadowAuthenticationChanged, object: nil)
    }

    func logout() {
        settings.token = ""
        userLogin = nil
        authStatus = "GitHub 登录后继续"
        state = .idle
        errorMessage = nil
        deviceCode = nil
        historyStore.clear()
        deliveryHistory = []
        KeychainTokenStore.deleteToken()
        saveSettings()
        NotificationCenter.default.post(name: .smartShadowAuthenticationChanged, object: nil)
    }

    func startPressRecording() async {
        guard state != .uploading, isAuthenticated else {
            if !isAuthenticated { errorMessage = "GitHub login is required." }
            return
        }

        let packetID = VoicePacketDescriptor.makePacketID()
        let audioURL = localPacketDirectory(packetID: packetID).appendingPathComponent("audio.m4a")
        activePacketID = packetID
        activeAudioURL = audioURL
        state = .recording
        errorMessage = nil
        await recorder.startRecording(to: audioURL)

        if let recorderError = recorder.errorMessage {
            state = .failed
            errorMessage = recorderError
        }
    }

    func finishPressRecording() {
        guard state == .recording else { return }
        recorder.stopRecording()
        guard let packetID = activePacketID, let audioURL = activeAudioURL else {
            state = .idle
            return
        }
        disableLegacyUpload(packetID: packetID, audioURL: audioURL)
    }

    func retryLastFailedLocalUpload() {
        guard let packetID = activePacketID, let audioURL = activeAudioURL else { return }
        disableLegacyUpload(packetID: packetID, audioURL: audioURL)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            errorMessage = error.localizedDescription
        }
    }

    private func disableLegacyUpload(packetID: String, audioURL: URL) {
        state = .failed
        errorMessage = "Raw audio GitHub upload is disabled. Use Shadow Command to process voice locally, review the text, then create an issue or comment with your GitHub identity."
        let descriptor = VoicePacketDescriptor(packetID: packetID, inboxPath: settings.inboxPath)
        let failed = VoicePacketDelivery(
            packetID: packetID,
            repositoryPath: descriptor.pendingDirectory,
            uploadedAt: ISO8601DateFormatter.localInternetDateTimeString(from: Date()),
            status: .failed,
            errorMessage: errorMessage
        )
        historyStore.record(failed)
        deliveryHistory = historyStore.deliveries
        _ = audioURL
    }

    private func localPacketDirectory(packetID: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SmartShadow", isDirectory: true)
            .appendingPathComponent("VoicePackets", isDirectory: true)
        return base.appendingPathComponent(packetID, isDirectory: true)
    }
}

extension Notification.Name {
    static let smartShadowAuthenticationChanged = Notification.Name("smartShadowAuthenticationChanged")
}
