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

    func testOnlyImplementedTargetsReceiveAutomaticExecution() {
        XCTAssertEqual(makeAction(targetKind: "pharos.local.complete_request").executionRoute, .local)
        XCTAssertEqual(makeAction(targetKind: "gitlab.mr.comment").executionRoute, .gitlabWriteback)
        XCTAssertEqual(makeAction(targetKind: "gitlab.issue.comment").executionRoute, .gitlabWriteback)
        XCTAssertEqual(makeAction(targetKind: "feishu.chat.reply").executionRoute, .approvalOnly)
        XCTAssertEqual(makeAction(targetKind: "unknown.external").executionRoute, .approvalOnly)
    }

    @MainActor
    func testWritebackMutationFailureRefreshesDurableState() async {
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST" {
                throw URLError(.networkConnectionLost)
            }
            let body: String
            if path == "/v0/today" {
                body = #"{"needs_decision":[],"needs_input":[],"watching":[],"handled":[],"noise":{"count":0}}"#
            } else {
                body = Self.emptyDetailJSON
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }

        let state = AppState(api: makeClient(token: validToken))
        state.selectedRequestId = "req_1"
        await state.executeApproved(makeAction(targetKind: "gitlab.mr.comment"))

        XCTAssertEqual(MockURLProtocol.requests.map(\.httpMethod), ["POST", "GET", "GET"])
        XCTAssertEqual(
            MockURLProtocol.requests.map { $0.url?.path ?? "" },
            [
                "/v0/actions/act_1/execute-approved",
                "/v0/today",
                "/v0/requests/req_1",
            ]
        )
        XCTAssertNotNil(state.selectedDetail)
        XCTAssertNotNil(state.errorMessage)
    }

    @MainActor
    func testWritebackConflictRefreshesDurableState() async {
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST" {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 409, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"error":"writeback_attempt_state_mismatch"}"#.utf8)
                )
            }
            let body = path == "/v0/today"
                ? #"{"needs_decision":[],"needs_input":[],"watching":[],"handled":[],"noise":{"count":0}}"#
                : Self.emptyDetailJSON
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }

        let state = AppState(api: makeClient(token: validToken))
        state.selectedRequestId = "req_1"
        await state.reconcile(makeAttempt())

        XCTAssertEqual(MockURLProtocol.requests.map(\.httpMethod), ["POST", "GET", "GET"])
        XCTAssertEqual(state.errorMessage, "writeback_attempt_state_mismatch")
        XCTAssertNotNil(state.selectedDetail)
    }

    @MainActor
    func testApproveThenSendFailureRefreshesDurableState() async {
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/approve") {
                let body = #"{"approval":{"id":"appr_1","action_id":"act_1","action_hash":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","decision":"approved","approved_body":null,"created_at":"2026-07-19T00:00:00Z"}}"#
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(body.utf8)
                )
            }
            if request.httpMethod == "POST" {
                throw URLError(.networkConnectionLost)
            }
            let body = path == "/v0/today"
                ? #"{"needs_decision":[],"needs_input":[],"watching":[],"handled":[],"noise":{"count":0}}"#
                : Self.emptyDetailJSON
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }

        let state = AppState(api: makeClient(token: validToken))
        state.selectedRequestId = "req_1"
        await state.approve(makeAction(targetKind: "gitlab.mr.comment"))

        XCTAssertEqual(MockURLProtocol.requests.map(\.httpMethod), ["POST", "POST", "GET", "GET"])
        XCTAssertEqual(
            MockURLProtocol.requests.map { $0.url?.path ?? "" },
            [
                "/v0/actions/act_1/approve",
                "/v0/actions/act_1/execute-approved",
                "/v0/today",
                "/v0/requests/req_1",
            ]
        )
        XCTAssertNotNil(state.selectedDetail)
        XCTAssertNotNil(state.errorMessage)
    }

    @MainActor
    func testUnsupportedExternalApprovalDoesNotCallWritebackRoute() async {
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let body: String
            if path.hasSuffix("/approve") {
                body = #"{"approval":{"id":"appr_1","action_id":"act_1","action_hash":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","decision":"approved","approved_body":null,"created_at":"2026-07-19T00:00:00Z"}}"#
            } else if path == "/v0/today" {
                body = #"{"needs_decision":[],"needs_input":[],"watching":[],"handled":[],"noise":{"count":0}}"#
            } else {
                body = Self.emptyDetailJSON
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }

        let state = AppState(api: makeClient(token: validToken))
        state.selectedRequestId = "req_1"
        await state.approve(makeAction(targetKind: "feishu.chat.reply"))

        XCTAssertEqual(MockURLProtocol.requests.map(\.httpMethod), ["POST", "GET", "GET"])
        XCTAssertFalse(
            MockURLProtocol.requests.contains {
                $0.url?.path.hasSuffix("/execute-approved") == true
            }
        )
    }

    private func makeAction(targetKind: String) -> ProposedAction {
        ProposedAction(
            id: "act_1",
            requestId: "req_1",
            title: "Action",
            body: "Body",
            targetKind: targetKind,
            targetRef: "target",
            risk: .l3,
            requiresApproval: true,
            status: .approved,
            payloadHash: "sha256:" + String(repeating: "a", count: 64),
            createdAt: "2026-07-19T00:00:00Z",
            updatedAt: "2026-07-19T00:00:00Z"
        )
    }

    private func makeAttempt() -> WritebackAttempt {
        WritebackAttempt(
            id: "wb_1",
            actionId: "act_1",
            approvalId: "appr_1",
            payloadHash: "sha256:" + String(repeating: "a", count: 64),
            targetKind: "gitlab.mr.comment",
            targetRef: "target",
            marker: "marker",
            status: .unknown,
            externalId: nil,
            externalUrl: nil,
            error: nil,
            createdAt: "2026-07-19T00:00:00Z",
            updatedAt: "2026-07-19T00:00:00Z",
            startedAt: nil,
            finishedAt: nil
        )
    }

    private static let emptyDetailJSON = #"{"request":{"id":"req_1","title":"Request","summary":"Summary","status":"executing","priority":"normal","risk":"l3","source_kind":"gitlab","source_signal_id":"sig_1","reason":"Reason","next_step":"Next","created_at":"2026-07-19T00:00:00Z","updated_at":"2026-07-19T00:00:00Z"},"actions":[],"writeback_attempts":[],"evidence":[],"timeline":[]}"#

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
