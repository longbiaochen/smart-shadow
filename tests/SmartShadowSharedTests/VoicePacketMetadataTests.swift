import XCTest
@testable import SmartShadowShared

final class VoicePacketMetadataTests: XCTestCase {
    func testMacOSMetadataUsesInboxContractWithoutIssueTarget() throws {
        let now = ISO8601DateFormatter().date(from: "2026-06-08T09:10:11Z")!
        let metadata = VoicePacketMetadata.make(
            packetID: "voice_20260608_091011_7f3a",
            now: now,
            user: "Longbiao",
            source: .macOS,
            calendar: .utc,
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(metadata.packetID, "voice_20260608_091011_7f3a")
        XCTAssertEqual(metadata.createdAt, "2026-06-08T09:10:11Z")
        XCTAssertEqual(metadata.user, "Longbiao")
        XCTAssertEqual(metadata.source, "macos")
        XCTAssertEqual(metadata.app, "SmartShadow")
        XCTAssertEqual(metadata.domain, "smart-shadow.bozhi.ai")
        XCTAssertEqual(metadata.audioFile, "audio.m4a")
        XCTAssertEqual(metadata.status, "pending")
        XCTAssertEqual(metadata.client.platform, "macOS")
        XCTAssertEqual(metadata.client.timezone, "GMT")
        XCTAssertEqual(metadata.client.locale, "zh-Hans")
        XCTAssertNil(metadata.target)

        let json = String(data: try JSONEncoder.smartShadowPretty.encode(metadata), encoding: .utf8)!
        XCTAssertTrue(json.contains(#""audio_file" : "audio.m4a""#))
        XCTAssertFalse(json.contains("issue_number"))
    }

    func testPendingPacketPathsUseDateAndPacketID() {
        let packet = VoicePacketDescriptor(packetID: "voice_20260608_091011_7f3a")

        XCTAssertEqual(packet.pendingDirectory, "inbox/pending/2026-06-08/voice_20260608_091011_7f3a")
        XCTAssertEqual(packet.audioPath, "inbox/pending/2026-06-08/voice_20260608_091011_7f3a/audio.m4a")
        XCTAssertEqual(packet.metadataPath, "inbox/pending/2026-06-08/voice_20260608_091011_7f3a/meta.json")
    }
}
