import Foundation
import XCTest
@testable import SmartShadowIOS

final class GitHubClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchRepositoriesParsesAndClassifiesLifeAreasAndBuckets() async throws {
        let session = makeSession { request in
            XCTAssertEqual(request.url?.path, "/user/repos")
            XCTAssertEqual(request.url?.query, "affiliation=owner,collaborator,organization_member&sort=updated&per_page=60")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            let data = """
            [
              {
                "id": 1,
                "name": "quant-trading",
                "full_name": "longbiaochen/quant-trading",
                "description": "finance revenue quant work",
                "open_issues_count": 9,
                "updated_at": "2026-06-10T10:00:00Z",
                "topics": ["finance", "urgent", "risk", "extra", "ignored"]
              },
              {
                "id": 2,
                "name": "mind-heal",
                "full_name": "longbiaochen/mind-heal",
                "description": "sleep and health notes",
                "open_issues_count": 0,
                "updated_at": "2026-06-09T10:00:00Z",
                "topics": ["health"]
              }
            ]
            """.data(using: .utf8)!
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let repos = try await GitHubClient(token: "token", session: session).fetchRepositories()

        XCTAssertEqual(repos.count, 2)
        XCTAssertEqual(repos[0].area, .money)
        XCTAssertEqual(repos[0].bucket, .urgent)
        XCTAssertEqual(repos[0].labels, ["finance", "urgent", "risk", "extra"])
        XCTAssertEqual(repos[0].status, "active")
        XCTAssertEqual(repos[1].area, .health)
        XCTAssertEqual(repos[1].status, "quiet")
    }

    func testFetchIssuesFiltersPullRequestsAndMarksDecisionIssues() async throws {
        let session = makeSession { request in
            let data: Data
            if request.url?.path == "/repos/longbiaochen/smart-shadow/issues" {
                data = """
                [
                  {
                    "id": 10,
                    "number": 12,
                    "title": "Choose repo board interaction",
                    "state": "open",
                    "labels": [{"name": "decision"}, {"name": "ios"}],
                    "assignee": {"login": "shadow"},
                    "updated_at": "2026-06-10T10:00:00Z",
                    "comments": 3,
                    "body": "Line one\\nLine two\\nLine three"
                  },
                  {
                    "id": 11,
                    "number": 13,
                    "title": "PR marker should be filtered",
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
            } else if request.url?.path == "/repos/longbiaochen/smart-shadow/issues/12/comments" {
                XCTAssertEqual(request.url?.query, "per_page=20")
                data = """
                [
                  {
                    "id": 201,
                    "body": "Need final simulator acceptance.\\nKeep writes confirmation-gated.",
                    "user": {"login": "bozhi-ai"},
                    "updated_at": "2026-06-10T12:00:00Z"
                  }
                ]
                """.data(using: .utf8)!
            } else {
                XCTFail("Unexpected path \(request.url?.path ?? "")")
                data = Data("[]".utf8)
            }
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let issues = try await GitHubClient(token: "token", session: session).fetchIssues(repoFullName: "longbiaochen/smart-shadow")

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].number, 12)
        XCTAssertEqual(issues[0].assignee, "shadow")
        XCTAssertEqual(issues[0].commentCount, 3)
        XCTAssertTrue(issues[0].needsDecision)
        XCTAssertEqual(issues[0].summary, "Line one\nLine two")
        XCTAssertEqual(issues[0].comments, ["@bozhi-ai: Need final simulator acceptance. Keep writes confirmation-gated."])
    }

    func testCreateIssueCommentSendsConfirmationGatedWriteRequest() async throws {
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/repos/longbiaochen/smart-shadow/issues/12/comments")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "smart-shadow-ios")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.bodyData()) as? [String: String])
            XCTAssertEqual(body["body"], "Smart Shadow suggestion")
            return (Data(#"{"id":1}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        }

        try await GitHubClient(token: "token", session: session).createIssueComment(
            repoFullName: "longbiaochen/smart-shadow",
            issueNumber: 12,
            body: "Smart Shadow suggestion"
        )
    }

    func testCreateIssueSendsConfirmationGatedWriteRequest() async throws {
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/repos/longbiaochen/smart-shadow/issues")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.bodyData()) as? [String: Any])
            XCTAssertEqual(body["title"] as? String, "Next action")
            XCTAssertEqual(body["body"] as? String, "Details")
            XCTAssertEqual(body["labels"] as? [String], ["smart-shadow", "shadow:inbox"])
            return (Data(#"{"id":1}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        }

        try await GitHubClient(token: "token", session: session).createIssue(
            repoFullName: "longbiaochen/smart-shadow",
            title: "Next action",
            body: "Details",
            labels: ["smart-shadow", "shadow:inbox"]
        )
    }

    private func makeSession(handler: @escaping (URLRequest) throws -> (Data, HTTPURLResponse)) -> URLSession {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class MockURLProtocol: URLProtocol {
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
