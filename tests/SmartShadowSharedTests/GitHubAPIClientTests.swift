import Foundation
@testable import SmartShadowGitHubAPI
import XCTest

final class GitHubAPIClientTests: XCTestCase {
    override func tearDown() {
        GitHubAPIMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchRepositoriesBuildsAuthenticatedRequestAndParsesRepos() async throws {
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/user/repos")
            XCTAssertEqual(request.url?.query, "affiliation=owner,collaborator,organization_member&sort=updated&per_page=60")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "smart-shadow-tests")
            let data = """
            [
              {
                "id": 1,
                "name": "smart-shadow",
                "full_name": "longbiaochen/smart-shadow",
                "description": "repo-first shadow console",
                "open_issues_count": 12,
                "updated_at": "2026-06-10T10:00:00Z",
                "topics": ["github", "shadow"]
              }
            ]
            """.data(using: .utf8)!
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let repos = try await GitHubAPIClient(token: "token", session: session, userAgent: "smart-shadow-tests").fetchRepositories()

        XCTAssertEqual(repos.count, 1)
        XCTAssertEqual(repos[0].fullName, "longbiaochen/smart-shadow")
        XCTAssertEqual(repos[0].openIssuesCount, 12)
        XCTAssertEqual(repos[0].topics, ["github", "shadow"])
    }

    func testFetchIssuesPreservesPullRequestMarkerForCallerFiltering() async throws {
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/repos/longbiaochen/smart-shadow/issues")
            XCTAssertEqual(request.url?.query, "state=open&per_page=40")
            let data = """
            [
              {
                "id": 10,
                "number": 12,
                "title": "Design repo board",
                "state": "open",
                "labels": [{"name": "decision"}, {"name": "ios"}],
                "assignee": {"login": "shadow"},
                "updated_at": "2026-06-10T10:00:00Z",
                "comments": 3,
                "body": "Line one\\nLine two"
              },
              {
                "id": 11,
                "number": 13,
                "title": "PR issue endpoint item",
                "state": "open",
                "labels": [],
                "assignee": null,
                "updated_at": "2026-06-10T11:00:00Z",
                "comments": 0,
                "pull_request": {},
                "body": null
              }
            ]
            """.data(using: .utf8)!
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let issues = try await GitHubAPIClient(token: "token", session: session, userAgent: "smart-shadow-tests")
            .fetchIssues(repoFullName: "longbiaochen/smart-shadow")

        XCTAssertEqual(issues.count, 2)
        XCTAssertFalse(issues[0].isPullRequest)
        XCTAssertTrue(issues[1].isPullRequest)
        XCTAssertEqual(issues[0].labels.map(\.name), ["decision", "ios"])
        XCTAssertEqual(issues[0].assignee?.login, "shadow")
    }

    func testFetchPullCountReturnsOpenPullsCount() async throws {
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/repos/longbiaochen/smart-shadow/pulls")
            XCTAssertEqual(request.url?.query, "state=open&per_page=100")
            let data = #"[{"id":1},{"id":2}]"#.data(using: .utf8)!
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let count = try await GitHubAPIClient(token: "token", session: session, userAgent: "smart-shadow-tests")
            .fetchPullCount(repoFullName: "longbiaochen/smart-shadow")

        XCTAssertEqual(count, 2)
    }

    func testFetchIssueCommentsBuildsReadRequestAndParsesComments() async throws {
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/repos/longbiaochen/smart-shadow/issues/12/comments")
            XCTAssertEqual(request.url?.query, "per_page=20")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            let data = """
            [
              {
                "id": 201,
                "body": "Need the repo card to show the next action.",
                "user": {"login": "bozhi-ai"},
                "updated_at": "2026-06-10T12:00:00Z"
              },
              {
                "id": 202,
                "body": null,
                "user": null,
                "updated_at": "2026-06-10T13:00:00Z"
              }
            ]
            """.data(using: .utf8)!
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let comments = try await GitHubAPIClient(token: "token", session: session, userAgent: "smart-shadow-tests")
            .fetchIssueComments(repoFullName: "longbiaochen/smart-shadow", issueNumber: 12)

        XCTAssertEqual(comments.count, 2)
        XCTAssertEqual(comments[0].id, 201)
        XCTAssertEqual(comments[0].user?.login, "bozhi-ai")
        XCTAssertEqual(comments[0].body, "Need the repo card to show the next action.")
    }

    func testCreateIssueCommentSendsJSONWriteRequest() async throws {
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/repos/longbiaochen/smart-shadow/issues/12/comments")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.bodyData()) as? [String: String])
            XCTAssertEqual(body["body"], "Smart Shadow suggestion")
            return (Data(#"{"id":1}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        }

        try await GitHubAPIClient(token: "token", session: session, userAgent: "smart-shadow-tests")
            .createIssueComment(repoFullName: "longbiaochen/smart-shadow", issueNumber: 12, body: "Smart Shadow suggestion")
    }

    func testCreateIssueAndRepositoryUseExpectedPayloads() async throws {
        var seenPaths: [String] = []
        let session = makeSession { request in
            seenPaths.append(request.url?.path ?? "")
            if request.url?.path == "/repos/longbiaochen/smart-shadow/issues" {
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.bodyData()) as? [String: Any])
                XCTAssertEqual(body["title"] as? String, "Next action")
                XCTAssertEqual(body["body"] as? String, "Details")
                XCTAssertEqual(body["labels"] as? [String], ["smart-shadow", "shadow:inbox"])
            } else if request.url?.path == "/user/repos" {
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.bodyData()) as? [String: Any])
                XCTAssertEqual(body["name"] as? String, "new-life-repo")
                XCTAssertEqual(body["description"] as? String, "Private repo")
                XCTAssertEqual(body["private"] as? Bool, true)
                XCTAssertEqual(body["auto_init"] as? Bool, true)
            } else {
                XCTFail("Unexpected path \(request.url?.path ?? "")")
            }
            return (Data(#"{"id":1}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        }

        let client = GitHubAPIClient(token: "token", session: session, userAgent: "smart-shadow-tests")
        try await client.createIssue(
            repoFullName: "longbiaochen/smart-shadow",
            title: "Next action",
            body: "Details",
            labels: ["smart-shadow", "shadow:inbox"]
        )
        try await client.createRepository(name: "new-life-repo", description: "Private repo")

        XCTAssertEqual(seenPaths, ["/repos/longbiaochen/smart-shadow/issues", "/user/repos"])
    }

    func testNonSuccessResponseThrowsStatusAndBody() async throws {
        let session = makeSession { request in
            let data = Data(#"{"message":"bad credentials"}"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }

        do {
            _ = try await GitHubAPIClient(token: "bad", session: session, userAgent: "smart-shadow-tests").fetchRepositories()
            XCTFail("Expected GitHubAPIError")
        } catch let error as GitHubAPIError {
            XCTAssertEqual(error, .requestFailed(statusCode: 401, body: #"{"message":"bad credentials"}"#))
        }
    }

    private func makeSession(handler: @escaping (URLRequest) throws -> (Data, HTTPURLResponse)) -> URLSession {
        GitHubAPIMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GitHubAPIMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class GitHubAPIMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    func bodyData() throws -> Data {
        if let httpBody {
            return httpBody
        }
        guard let httpBodyStream else {
            return Data()
        }
        httpBodyStream.open()
        defer { httpBodyStream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while httpBodyStream.hasBytesAvailable {
            let count = httpBodyStream.read(buffer, maxLength: bufferSize)
            if count < 0 {
                throw httpBodyStream.streamError ?? URLError(.cannotDecodeContentData)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}
