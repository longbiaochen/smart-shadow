import Foundation
import XCTest
@testable import SmartShadowShared

final class GitHubInboxUploaderTests: XCTestCase {
    func testLegacyVoicePacketUploadIsDisabled() async throws {
        let api = RecordingGitHubContentAPI()
        let uploader = GitHubInboxUploader(
            owner: "longbiaochen",
            repo: "life-os",
            token: "token",
            contentAPI: api
        )
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("audio.m4a")
        try FileManager.default.createDirectory(at: audioURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("audio-bytes".utf8).write(to: audioURL)

        do {
            _ = try await uploader.uploadVoicePacket(
                VoicePacketUpload(
                    packetID: "voice_20260608_091011_7f3a",
                    audioURL: audioURL,
                    user: "Longbiao",
                    source: .macOS
                ),
                now: ISO8601DateFormatter().date(from: "2026-06-08T09:10:11Z")!
            )
            XCTFail("Expected legacy audio upload to be disabled.")
        } catch let error as GitHubInboxError {
            XCTAssertEqual(error, .legacyAudioUploadDisabled)
        }

        XCTAssertEqual(api.puts, [])
    }
}

private final class RecordingGitHubContentAPI: GitHubContentAPI {
    struct Put: Equatable {
        var owner: String
        var repo: String
        var path: String
        var data: Data
        var message: String
        var token: String
    }

    private(set) var puts: [Put] = []

    func putContent(owner: String, repo: String, path: String, data: Data, message: String, token: String) async throws {
        puts.append(Put(owner: owner, repo: repo, path: path, data: data, message: message, token: token))
    }
}
