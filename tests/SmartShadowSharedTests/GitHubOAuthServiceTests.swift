import Foundation
@testable import SmartShadowGitHubAPI
import XCTest

final class GitHubOAuthServiceTests: XCTestCase {
    override func tearDown() {
        GitHubOAuthMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testRequestDeviceCodeUsesSharedOAuthHeadersAndFormBody() async throws {
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://github.com/login/device/code")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "smart-shadow-ios")
            let body = String(data: try request.bodyData(), encoding: .utf8)
            XCTAssertEqual(body, "client_id=client-123&scope=repo%20read:user")
            let data = """
            {
              "device_code": "device-123",
              "user_code": "ABCD-EFGH",
              "verification_uri": "https://github.com/login/device",
              "expires_in": 900,
              "interval": 5
            }
            """.data(using: .utf8)!
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let service = GitHubOAuthService(session: session, userAgent: "smart-shadow-ios")
        let response = try await service.requestDeviceCode(clientID: " client-123 ")

        XCTAssertEqual(response.deviceCode, "device-123")
        XCTAssertEqual(response.userCode, "ABCD-EFGH")
        XCTAssertEqual(response.interval, 5)
    }

    func testValidateUserUsesBearerTokenAndPlatformUserAgent() async throws {
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/user")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gho_token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "smart-shadow-macos")
            return (Data(#"{"login":"bozhi-ai"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let user = try await GitHubOAuthService(session: session, userAgent: "smart-shadow-macos")
            .validateUser(token: "gho_token")

        XCTAssertEqual(user.login, "bozhi-ai")
    }

    func testRequestFailureIncludesStatusAndBody() async throws {
        let session = makeSession { request in
            let data = Data(#"{"error":"bad_verification_code"}"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!)
        }

        do {
            _ = try await GitHubOAuthService(session: session, userAgent: "smart-shadow-tests")
                .requestDeviceCode(clientID: "client-123")
            XCTFail("Expected GitHubOAuthError")
        } catch let error as GitHubOAuthError {
            XCTAssertEqual(error, .requestFailed(400, #"{"error":"bad_verification_code"}"#))
        }
    }

    private func makeSession(handler: @escaping (URLRequest) throws -> (Data, HTTPURLResponse)) -> URLSession {
        GitHubOAuthMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GitHubOAuthMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class GitHubOAuthMockURLProtocol: URLProtocol {
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
