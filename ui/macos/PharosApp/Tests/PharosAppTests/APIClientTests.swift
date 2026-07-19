import Foundation
import XCTest
@testable import PharosApp

final class APIClientTests: XCTestCase {
    private let validToken = String(repeating: "a", count: 64)

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    func testInvalidCapabilitiesFailBeforeTransport() async {
        let invalidTokens: [String?] = [
            nil,
            "short",
            String(repeating: "A", count: 64),
        ]

        for token in invalidTokens {
            let client = makeClient(token: token)
            do {
                _ = try await client.sources()
                XCTFail("invalid capability unexpectedly reached transport")
            } catch {
                // The configuration error is the expected result.
            }
        }

        XCTAssertEqual(MockURLProtocol.requests.count, 0)
    }

    func testValidCapabilityIsExactOnGetAndPost() async throws {
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let body: String
            if path == "/v0/sources" {
                body = #"{"sources":[]}"#
            } else {
                body = #"{"approval":{"id":"appr_1","action_id":"act_1","action_hash":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","decision":"approved","approved_body":null,"created_at":"2026-07-19T00:00:00Z"}}"#
            }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["content-type": "application/json"]
                )!,
                Data(body.utf8)
            )
        }

        let client = makeClient(token: validToken)
        _ = try await client.sources()
        _ = try await client.approve(
            actionId: "act_1",
            expectedPayloadHash: "sha256:" + String(repeating: "a", count: 64)
        )

        XCTAssertEqual(MockURLProtocol.requests.count, 2)
        for request in MockURLProtocol.requests {
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer \(validToken)"
            )
        }
        XCTAssertEqual(MockURLProtocol.requests.map(\.httpMethod), ["GET", "POST"])
    }

    private func makeClient(token: String?) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return APIClient(
            baseURL: URL(string: "http://127.0.0.1:8765")!,
            capabilityToken: token,
            session: URLSession(configuration: configuration)
        )
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requests: [URLRequest] = []
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        requests = []
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
