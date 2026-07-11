import Foundation

private enum APIClientConfigurationError: LocalizedError {
    case invalidCapabilityToken

    var errorDescription: String? {
        "PHAROS_CAPABILITY_TOKEN must be set to exactly 64 lowercase hexadecimal characters."
    }
}

struct APIClient {
    var baseURL: URL = URL(string: "http://127.0.0.1:8765")!
    var capabilityToken: String? = ProcessInfo.processInfo.environment["PHAROS_CAPABILITY_TOKEN"]

    private func endpoint(_ path: String) -> URL {
        URL(string: path, relativeTo: baseURL)!.absoluteURL
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    func today() async throws -> TodaySnapshot {
        try await request(path: "/v0/today")
    }

    func requestDetail(id: String) async throws -> RequestDetail {
        try await request(path: "/v0/requests/\(id)")
    }

    func capture(_ payload: CapturePayload) async throws -> CaptureResponse {
        try await request(path: "/v0/capture", method: "POST", body: payload)
    }

    func sources() async throws -> SourcesResponse {
        try await request(path: "/v0/sources")
    }

    func patchSource(id: String, payload: SourcePatchPayload) async throws -> SourceResponse {
        try await request(path: "/v0/sources/\(id)", method: "PATCH", body: payload)
    }

    func approve(actionId: String, expectedPayloadHash: String) async throws -> ApprovalResponse {
        struct Payload: Encodable { let expectedPayloadHash: String }
        return try await request(
            path: "/v0/actions/\(actionId)/approve",
            method: "POST",
            body: Payload(expectedPayloadHash: expectedPayloadHash)
        )
    }

    func editAndApprove(actionId: String, body: String, expectedPayloadHash: String) async throws -> ApprovalResponse {
        struct Payload: Encodable {
            let body: String
            let expectedPayloadHash: String
        }
        return try await request(
            path: "/v0/actions/\(actionId)/edit-and-approve",
            method: "POST",
            body: Payload(body: body, expectedPayloadHash: expectedPayloadHash)
        )
    }

    func reject(actionId: String, expectedPayloadHash: String) async throws -> ApprovalResponse {
        struct Payload: Encodable { let expectedPayloadHash: String }
        return try await request(
            path: "/v0/actions/\(actionId)/reject",
            method: "POST",
            body: Payload(expectedPayloadHash: expectedPayloadHash)
        )
    }

    func executeLocal(actionId: String) async throws -> ActionResponse {
        try await request(path: "/v0/actions/\(actionId)/execute-local", method: "POST", emptyBody: true)
    }

    private func request<T: Decodable>(path: String, method: String = "GET") async throws -> T {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        try authorize(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func request<T: Decodable, Body: Encodable>(path: String, method: String, body: Body) async throws -> T {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try encoder.encode(body)
        try authorize(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func request<T: Decodable>(path: String, method: String, emptyBody: Bool) async throws -> T {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        if emptyBody {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = Data("{}".utf8)
        }
        try authorize(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            if let apiError = try? decoder.decode(APIErrorResponse.self, from: data) {
                throw apiError
            }
            throw URLError(.badServerResponse)
        }
    }

    private func authorize(_ request: inout URLRequest) throws {
        guard let capabilityToken,
              capabilityToken.utf8.count == 64,
              capabilityToken.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }) else {
            throw APIClientConfigurationError.invalidCapabilityToken
        }
        request.setValue("Bearer \(capabilityToken)", forHTTPHeaderField: "Authorization")
    }
}
