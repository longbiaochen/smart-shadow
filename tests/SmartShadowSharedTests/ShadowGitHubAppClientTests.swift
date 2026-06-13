import Foundation
@testable import SmartShadowGitHubAPI
import XCTest

final class ShadowGitHubAppClientTests: XCTestCase {
    override func tearDown() {
        ShadowGitHubAppMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testUsesInstallationTokenForShadowBotIssueOperations() async throws {
        var seen: [(method: String, path: String, body: [String: Any])] = []
        let session = makeSession { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer installation-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "smart-shadow-shadow-app-tests")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.shadowAppBodyData()) as? [String: Any])
            seen.append((request.httpMethod ?? "", request.url?.path ?? "", body))
            return (Data(#"{"ok":true}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let client = ShadowGitHubAppClient(
            installationToken: "installation-token",
            session: session,
            userAgent: "smart-shadow-shadow-app-tests"
        )
        try await client.commentIssue(repoFullName: "owner/repo", issueNumber: 12, body: "已接收任务，正在拆解。")
        try await client.updateIssueTitle(repoFullName: "owner/repo", issueNumber: 12, title: "Implement local voice flow")
        try await client.setLabels(repoFullName: "owner/repo", issueNumber: 12, labels: ["smart-shadow", "shadow:triaging"])

        XCTAssertEqual(seen.map(\.method), ["POST", "PATCH", "PATCH"])
        XCTAssertEqual(seen.map(\.path), [
            "/repos/owner/repo/issues/12/comments",
            "/repos/owner/repo/issues/12",
            "/repos/owner/repo/issues/12"
        ])
        XCTAssertEqual(seen[0].body["body"] as? String, "已接收任务，正在拆解。")
        XCTAssertEqual(seen[1].body["title"] as? String, "Implement local voice flow")
        XCTAssertEqual(seen[2].body["labels"] as? [String], ["smart-shadow", "shadow:triaging"])
    }

    func testCreatesBranchAndPullRequestAsShadowApp() async throws {
        var seen: [(path: String, body: [String: Any])] = []
        let session = makeSession { request in
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.shadowAppBodyData()) as? [String: Any])
            seen.append((request.url?.path ?? "", body))
            return (Data(#"{"ok":true}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        }

        let client = ShadowGitHubAppClient(installationToken: "installation-token", session: session)
        try await client.createBranch(repoFullName: "owner/repo", branchName: "shadow/local-voice", fromSHA: "abc123")
        try await client.createPullRequest(
            repoFullName: "owner/repo",
            title: "Implement local voice flow",
            head: "shadow/local-voice",
            base: "main",
            body: "PR summary"
        )

        XCTAssertEqual(seen[0].path, "/repos/owner/repo/git/refs")
        XCTAssertEqual(seen[0].body["ref"] as? String, "refs/heads/shadow/local-voice")
        XCTAssertEqual(seen[0].body["sha"] as? String, "abc123")
        XCTAssertEqual(seen[1].path, "/repos/owner/repo/pulls")
        XCTAssertEqual(seen[1].body["title"] as? String, "Implement local voice flow")
        XCTAssertEqual(seen[1].body["head"] as? String, "shadow/local-voice")
        XCTAssertEqual(seen[1].body["base"] as? String, "main")
        XCTAssertEqual(seen[1].body["body"] as? String, "PR summary")
    }

    private func makeSession(handler: @escaping (URLRequest) throws -> (Data, HTTPURLResponse)) -> URLSession {
        ShadowGitHubAppMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ShadowGitHubAppMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class ShadowGitHubAppMockURLProtocol: URLProtocol {
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
    func shadowAppBodyData() throws -> Data {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }
}
