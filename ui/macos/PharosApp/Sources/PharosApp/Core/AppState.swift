import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let api: APIClient

    @Published var snapshot: TodaySnapshot?
    @Published var selectedRequestId: String?
    @Published var selectedDetail: RequestDetail?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showCapture = false

    init(api: APIClient) {
        self.api = api
    }

    func refreshToday() async {
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await api.today()
            errorMessage = nil
        } catch {
            errorMessage = readable(error)
        }
    }

    func select(_ request: WorkRequest) async {
        selectedRequestId = request.id
        await loadDetail(id: request.id)
    }

    func select(_ card: DecisionCard) async {
        selectedRequestId = card.requestId
        await loadDetail(id: card.requestId)
    }

    func loadDetail(id: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            selectedDetail = try await api.requestDetail(id: id)
            errorMessage = nil
        } catch {
            errorMessage = readable(error)
        }
    }

    func capture(title: String?, body: String, url: String?) async {
        do {
            let response = try await api.capture(CapturePayload(title: title?.nilIfBlank, body: body, url: url?.nilIfBlank, actor: "swiftui"))
            showCapture = false
            await refreshToday()
            await loadDetail(id: response.request.id)
        } catch {
            errorMessage = readable(error)
        }
    }

    func approve(_ action: ProposedAction, executeAfterApproval: Bool = true) async {
        do {
            _ = try await api.approve(actionId: action.id)
            if executeAfterApproval {
                _ = try await api.executeLocal(actionId: action.id)
            }
            await refreshCurrent()
        } catch {
            errorMessage = readable(error)
        }
    }

    func editAndApprove(_ action: ProposedAction, body: String, executeAfterApproval: Bool = true) async {
        do {
            _ = try await api.editAndApprove(actionId: action.id, body: body)
            if executeAfterApproval {
                _ = try await api.executeLocal(actionId: action.id)
            }
            await refreshCurrent()
        } catch {
            errorMessage = readable(error)
        }
    }

    func reject(_ action: ProposedAction) async {
        do {
            _ = try await api.reject(actionId: action.id)
            await refreshCurrent()
        } catch {
            errorMessage = readable(error)
        }
    }

    private func refreshCurrent() async {
        await refreshToday()
        if let selectedRequestId {
            await loadDetail(id: selectedRequestId)
        }
    }

    private func readable(_ error: Error) -> String {
        if let apiError = error as? APIErrorResponse { return apiError.error }
        return error.localizedDescription
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
