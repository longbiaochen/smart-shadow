import XCTest
@testable import SmartShadowShared

final class ShadowGitHubActionExecutorTests: XCTestCase {
    func testDoesNotExecuteWithoutConfirmedAction() async {
        let client = FakeWriteClient()

        let result = await ShadowGitHubActionExecutor.execute(plan: nil, token: "token", client: client)

        XCTAssertEqual(result, .missingAction)
        let calls = await client.recordedCalls()
        XCTAssertEqual(calls, [])
    }

    func testDoesNotExecuteWithoutToken() async {
        let client = FakeWriteClient()
        let plan = makePlan(kind: .createIssue)

        let result = await ShadowGitHubActionExecutor.execute(plan: plan, token: "  ", client: client)

        XCTAssertEqual(result, .missingToken)
        let calls = await client.recordedCalls()
        XCTAssertEqual(calls, [])
    }

    func testExecutesIssueCommentAfterConfirmationGate() async {
        let client = FakeWriteClient()
        let plan = makePlan(kind: .issueComment, issueNumber: 42)

        let result = await ShadowGitHubActionExecutor.execute(plan: plan, token: "token", client: client)

        XCTAssertEqual(result, .executed)
        let calls = await client.recordedCalls()
        XCTAssertEqual(calls, [.issueComment("owner/repo", 42, "body")])
    }

    func testExecutesCreateIssueAfterConfirmationGate() async {
        let client = FakeWriteClient()
        let plan = makePlan(kind: .createIssue, issueTitle: "Next action")

        let result = await ShadowGitHubActionExecutor.execute(plan: plan, token: "token", client: client)

        XCTAssertEqual(result, .executed)
        let calls = await client.recordedCalls()
        XCTAssertEqual(calls, [.createIssue("owner/repo", "Next action", "body", [])])
    }

    func testExecutesCreateRepoAfterConfirmationGate() async {
        let client = FakeWriteClient()
        let plan = makePlan(kind: .createRepo, repoName: "life-os-radar", repoDescription: "Repo-first console")

        let result = await ShadowGitHubActionExecutor.execute(plan: plan, token: "token", client: client)

        XCTAssertEqual(result, .executed)
        let calls = await client.recordedCalls()
        XCTAssertEqual(calls, [.createRepo("life-os-radar", "Repo-first console")])
    }

    private func makePlan(
        kind: PlannedGitHubActionKind,
        issueNumber: Int? = nil,
        issueTitle: String? = nil,
        repoName: String? = nil,
        repoDescription: String? = nil
    ) -> ShadowGitHubActionPlan {
        ShadowGitHubActionPlan(
            kind: kind,
            title: "title",
            repoFullName: "owner/repo",
            repoName: repoName,
            repoDescription: repoDescription,
            issueNumber: issueNumber,
            issueTitle: issueTitle,
            body: "body",
            suggestedAction: "suggestion"
        )
    }
}

private actor FakeWriteClient: ShadowGitHubWriteClient {
    enum Call: Equatable {
        case issueComment(String, Int, String)
        case createIssue(String, String, String, [String])
        case createRepo(String, String?)
    }

    private(set) var calls: [Call] = []

    func recordedCalls() -> [Call] {
        calls
    }

    func createIssueComment(repoFullName: String, issueNumber: Int, body: String) async throws {
        calls.append(.issueComment(repoFullName, issueNumber, body))
    }

    func createIssue(repoFullName: String, title: String, body: String, labels: [String]) async throws {
        calls.append(.createIssue(repoFullName, title, body, labels))
    }

    func createRepository(name: String, description: String?) async throws {
        calls.append(.createRepo(name, description))
    }
}
