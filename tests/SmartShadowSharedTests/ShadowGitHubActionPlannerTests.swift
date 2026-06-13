import XCTest
@testable import SmartShadowShared

final class ShadowGitHubActionPlannerTests: XCTestCase {
    func testPlansIssueCommentWhenIssueIsSelected() {
        let plan = ShadowGitHubActionPlanner.plan(
            command: "Summarize the decision and ask for approval.",
            repo: ShadowRepoActionContext(name: "smart-shadow", fullName: "longbiaochen/smart-shadow", agentState: "watching"),
            issue: ShadowIssueActionContext(number: 12, title: "Design repo board"),
            allowCreateRepoWithoutSelection: true
        )

        XCTAssertEqual(plan?.kind, .issueComment)
        XCTAssertEqual(plan?.repoFullName, "longbiaochen/smart-shadow")
        XCTAssertEqual(plan?.issueNumber, 12)
        XCTAssertTrue(plan?.body.contains("Issue: #12 Design repo board") == true)
        XCTAssertTrue(plan?.suggestedAction.contains("confirmation-gated issue comment") == true)
    }

    func testPlansCreateIssueWhenOnlyRepoIsSelected() {
        let plan = ShadowGitHubActionPlanner.plan(
            command: "Draft acceptance checklist",
            repo: ShadowRepoActionContext(name: "smart-shadow", fullName: "longbiaochen/smart-shadow", agentState: "executing"),
            issue: nil,
            allowCreateRepoWithoutSelection: false
        )

        XCTAssertEqual(plan?.kind, .createIssue)
        XCTAssertEqual(plan?.issueTitle, "新任务")
        XCTAssertEqual(plan?.labels, ["smart-shadow", "shadow:inbox"])
        XCTAssertTrue(plan?.body.contains("Agent state: executing") == true)
    }

    func testPlansCreateIssueAsFinalTextTaskWithoutAudioArtifacts() {
        let plan = ShadowGitHubActionPlanner.plan(
            command: "Draft acceptance checklist\nMake it simulator-verifiable.",
            repo: ShadowRepoActionContext(name: "smart-shadow", fullName: "longbiaochen/smart-shadow", agentState: "executing"),
            issue: nil,
            allowCreateRepoWithoutSelection: false
        )

        XCTAssertEqual(plan?.kind, .createIssue)
        XCTAssertTrue(plan?.body.contains("## Background") == true)
        XCTAssertTrue(plan?.body.contains("## Goal") == true)
        XCTAssertTrue(plan?.body.contains("## Acceptance Criteria") == true)
        XCTAssertTrue(plan?.body.contains("Source: Smart Shadow") == true)
        XCTAssertTrue(plan?.body.contains("audio: not_uploaded") == true)
        XCTAssertTrue(plan?.body.contains("shadow_status: inbox") == true)
        XCTAssertTrue(plan?.body.contains("Draft acceptance checklist") == true)
        XCTAssertFalse(plan?.body.contains("audio.m4a") == true)
        XCTAssertFalse(plan?.body.contains("audio_file") == true)
        XCTAssertFalse(plan?.body.contains("audio_path") == true)
        XCTAssertFalse(plan?.body.contains("raw transcript") == true)
    }

    func testPlansPrivateRepoWhenNoRepoIsSelectedAndAllowed() {
        let plan = ShadowGitHubActionPlanner.plan(
            command: "Create repo Life OS Radar\nQuiet repo-first console",
            repo: nil,
            issue: nil,
            allowCreateRepoWithoutSelection: true
        )

        XCTAssertEqual(plan?.kind, .createRepo)
        XCTAssertEqual(plan?.repoName, "life-os-radar")
        XCTAssertEqual(plan?.repoDescription, "Quiet repo-first console")
        XCTAssertTrue(plan?.title.contains("life-os-radar") == true)
    }

    func testDoesNotPlanRepoCreationWithoutSelectionWhenDisallowed() {
        let plan = ShadowGitHubActionPlanner.plan(
            command: "Create repo Life OS Radar",
            repo: nil,
            issue: nil,
            allowCreateRepoWithoutSelection: false
        )

        XCTAssertNil(plan)
    }
}
