import Foundation

struct APIClient {
    var baseURL: URL = URL(string: "http://127.0.0.1:8765")!

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

    func approve(actionId: String) async throws -> ApprovalResponse {
        try await request(path: "/v0/actions/\(actionId)/approve", method: "POST", emptyBody: true)
    }

    func editAndApprove(actionId: String, body: String) async throws -> ApprovalResponse {
        struct Payload: Encodable { let body: String }
        return try await request(path: "/v0/actions/\(actionId)/edit-and-approve", method: "POST", body: Payload(body: body))
    }

    func reject(actionId: String) async throws -> ApprovalResponse {
        try await request(path: "/v0/actions/\(actionId)/reject", method: "POST", emptyBody: true)
    }

    func executeLocal(actionId: String) async throws -> ActionResponse {
        try await request(path: "/v0/actions/\(actionId)/execute-local", method: "POST", emptyBody: true)
    }

    private func request<T: Decodable>(path: String, method: String = "GET") async throws -> T {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func request<T: Decodable, Body: Encodable>(path: String, method: String, body: Body) async throws -> T {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try encoder.encode(body)
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
}
