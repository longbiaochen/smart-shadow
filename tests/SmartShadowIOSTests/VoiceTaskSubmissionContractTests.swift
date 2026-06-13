import XCTest
@testable import SmartShadowIOS

@MainActor
final class VoiceTaskSubmissionContractTests: XCTestCase {
    func testFollowUpURLParsingKeepsIssueTarget() {
        let context = FollowUpContext.parse(
            url: URL(string: "https://smart-shadow.bozhi.ai/followup?repo=longbiaochen/life-os&issue=123")!
        )

        XCTAssertEqual(context, FollowUpContext(repo: "longbiaochen/life-os", issueNumber: 123))
    }

    func testGeneratedIssueBodyContainsFinalTextAndNoVoicePacketFields() {
        let store = ShadowConsoleStore()
        let repo = ShadowConsoleStore.previewRepos[0]
        store.focus(repo: repo, issue: nil)
        store.commandText = "整理 Smart Shadow 本地语音处理验收"

        store.generateSuggestion()

        let body = store.pendingAction?.body ?? ""
        XCTAssertTrue(body.contains("## Background"))
        XCTAssertTrue(body.contains("## Goal"))
        XCTAssertTrue(body.contains("Source: Smart Shadow"))
        XCTAssertTrue(body.contains("整理 Smart Shadow 本地语音处理验收"))
        XCTAssertFalse(body.contains("audio.m4a"))
        XCTAssertFalse(body.contains("audio_file"))
        XCTAssertFalse(body.contains("audio_path"))
        XCTAssertFalse(body.contains("meta.json"))
        XCTAssertFalse(body.contains("inbox/pending"))
    }
}
