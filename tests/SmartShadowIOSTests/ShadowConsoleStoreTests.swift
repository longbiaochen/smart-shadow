import XCTest
@testable import SmartShadowIOS

@MainActor
final class ShadowConsoleStoreTests: XCTestCase {
    func testEmptyCommandDoesNotGenerateAction() {
        let store = ShadowConsoleStore()
        store.focus(repo: ShadowConsoleStore.previewRepos[0], issue: nil)
        store.commandText = "   "

        store.generateSuggestion()

        XCTAssertNil(store.pendingAction)
        XCTAssertEqual(store.commandStatus, "Enter or dictate a command first.")
    }

    func testRepoCommandGeneratesConfirmationGatedIssue() {
        let store = ShadowConsoleStore()
        let repo = ShadowConsoleStore.previewRepos[0]
        store.focus(repo: repo, issue: nil)
        store.commandText = "Draft iOS simulator acceptance checklist"

        store.generateSuggestion()

        XCTAssertEqual(store.pendingAction?.kind, .createIssue)
        XCTAssertEqual(store.pendingAction?.repoFullName, repo.fullName)
        XCTAssertEqual(store.pendingAction?.issueTitle, "新任务")
        XCTAssertEqual(store.pendingAction?.labels, ["smart-shadow", "shadow:inbox"])
        XCTAssertTrue(store.pendingAction?.body.contains("Agent state: \(repo.agentState)") == true)
        XCTAssertTrue(store.suggestedAction.contains("confirmation-gated issue") == true)
    }

    func testIssueCommandGeneratesConfirmationGatedComment() {
        let store = ShadowConsoleStore()
        let repo = ShadowConsoleStore.previewRepos[0]
        let issue = ShadowConsoleStore.previewIssues[0]
        store.focus(repo: repo, issue: issue)
        store.commandText = "Ask for a decision on the interaction direction"

        store.generateSuggestion()

        XCTAssertEqual(store.pendingAction?.kind, .issueComment)
        XCTAssertEqual(store.pendingAction?.repoFullName, repo.fullName)
        XCTAssertEqual(store.pendingAction?.issueNumber, issue.number)
        XCTAssertTrue(store.pendingAction?.body.contains("Issue: #\(issue.number) \(issue.title)") == true)
        XCTAssertTrue(store.suggestedAction.contains("confirmation-gated issue comment") == true)
    }
}
