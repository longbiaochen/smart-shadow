import XCTest
@testable import SmartShadowShared

final class SmartShadowIssueParserTests: XCTestCase {
    func testParsesFinalTextVoiceIssueMetadata() {
        let issue = SmartShadowIssueEnvelope(
            title: "新任务",
            labels: ["smart-shadow", "shadow:inbox"],
            body: """
            请实现本地语音提交 GitHub issue。

            ---

            <!-- smart-shadow
            source: ios
            input: voice
            audio: not_uploaded
            created_by: user
            shadow_status: inbox
            -->
            """
        )

        let context = SmartShadowIssueParser.parse(issue)

        XCTAssertEqual(context?.source, "ios")
        XCTAssertEqual(context?.input, "voice")
        XCTAssertEqual(context?.audio, "not_uploaded")
        XCTAssertEqual(context?.createdBy, "user")
        XCTAssertEqual(context?.shadowStatus, "inbox")
        XCTAssertEqual(context?.isSmartShadowTask, true)
        XCTAssertEqual(context?.isFinalTextTask, true)
    }

    func testRejectsLegacyAudioPayloadAsFinalTextTask() {
        let issue = SmartShadowIssueEnvelope(
            title: "Legacy voice packet",
            labels: ["smart-shadow"],
            body: """
            audio_path: /tmp/audio.m4a
            raw transcript: hello

            <!-- smart-shadow
            source: macos
            input: voice
            audio: not_uploaded
            -->
            """
        )

        let context = SmartShadowIssueParser.parse(issue)

        XCTAssertEqual(context?.isSmartShadowTask, true)
        XCTAssertEqual(context?.isFinalTextTask, false)
    }

    func testIgnoresNonSmartShadowIssue() {
        let issue = SmartShadowIssueEnvelope(title: "Normal issue", labels: ["bug"], body: "Fix typo")

        XCTAssertNil(SmartShadowIssueParser.parse(issue))
    }
}
