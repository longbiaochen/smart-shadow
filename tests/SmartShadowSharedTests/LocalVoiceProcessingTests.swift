import XCTest
@testable import SmartShadowShared

final class LocalVoiceProcessingTests: XCTestCase {
    func testPipelineReturnsPolishedFinalTextWithoutAudioUploadMetadata() async throws {
        let pipeline = LocalVoiceProcessingPipeline(client: FakeLocalVoiceProcessingClient())
        let result = try await pipeline.process(audioURL: URL(fileURLWithPath: "/tmp/task.m4a"))

        XCTAssertEqual(result.transcript, "修一下 iOS 语音入口")
        XCTAssertEqual(result.polishedText, "修复 iOS 语音入口，并补充本地验收。")
        XCTAssertFalse(result.polishedText.contains("audio.m4a"))
        XCTAssertFalse(result.polishedText.contains("audio_file"))
        XCTAssertFalse(result.polishedText.contains("audio_path"))
    }
}

private struct FakeLocalVoiceProcessingClient: LocalVoiceProcessingClient {
    func transcribe(audioURL: URL) async throws -> String {
        "修一下 iOS 语音入口"
    }

    func polish(transcript: String) async throws -> String {
        XCTAssertEqual(transcript, "修一下 iOS 语音入口")
        return "修复 iOS 语音入口，并补充本地验收。"
    }
}
