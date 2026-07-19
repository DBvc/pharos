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
        var approvalCompleted = false
        do {
            _ = try await api.approve(
                actionId: action.id,
                expectedPayloadHash: action.payloadHash
            )
            approvalCompleted = true
            if executeAfterApproval {
                switch action.executionRoute {
                case .local:
                    _ = try await api.executeLocal(actionId: action.id)
                case .gitlabWriteback:
                    _ = try await api.executeApproved(actionId: action.id)
                case .approvalOnly:
                    break
                }
            }
            await refreshCurrent()
        } catch {
            if approvalCompleted {
                await handleDurableMutationError(error)
            } else {
                await handleActionMutationError(error)
            }
        }
    }

    func editAndApprove(_ action: ProposedAction, body: String, executeAfterApproval: Bool = true) async {
        var approvalCompleted = false
        do {
            _ = try await api.editAndApprove(
                actionId: action.id,
                body: body,
                expectedPayloadHash: action.payloadHash
            )
            approvalCompleted = true
            if executeAfterApproval {
                switch action.executionRoute {
                case .local:
                    _ = try await api.executeLocal(actionId: action.id)
                case .gitlabWriteback:
                    _ = try await api.executeApproved(actionId: action.id)
                case .approvalOnly:
                    break
                }
            }
            await refreshCurrent()
        } catch {
            if approvalCompleted {
                await handleDurableMutationError(error)
            } else {
                await handleActionMutationError(error)
            }
        }
    }

    func reject(_ action: ProposedAction) async {
        do {
            _ = try await api.reject(
                actionId: action.id,
                expectedPayloadHash: action.payloadHash
            )
            await refreshCurrent()
        } catch {
            await handleActionMutationError(error)
        }
    }

    func executeApproved(_ action: ProposedAction) async {
        do {
            _ = try await api.executeApproved(actionId: action.id)
            await refreshCurrent()
        } catch {
            await handleDurableMutationError(error)
        }
    }

    func reconcile(_ attempt: WritebackAttempt) async {
        do {
            _ = try await api.reconcileWriteback(attemptId: attempt.id)
            await refreshCurrent()
        } catch {
            await handleDurableMutationError(error)
        }
    }

    func abandon(_ attempt: WritebackAttempt) async {
        do {
            _ = try await api.abandonWriteback(attemptId: attempt.id)
            await refreshCurrent()
        } catch {
            await handleDurableMutationError(error)
        }
    }

    @discardableResult
    private func refreshCurrent() async -> Bool {
        await refreshToday()
        guard errorMessage == nil else { return false }
        if let selectedRequestId {
            await loadDetail(id: selectedRequestId)
            return errorMessage == nil
        }
        return true
    }

    private func handleActionMutationError(_ error: Error) async {
        guard let apiError = error as? APIErrorResponse,
              apiError.error == "stale_action" else {
            errorMessage = readable(error)
            return
        }
        if await refreshCurrent() {
            errorMessage = "This draft changed. Review the refreshed action before deciding."
        } else {
            selectedDetail = nil
        }
    }

    private func handleDurableMutationError(_ error: Error) async {
        let originalMessage = readable(error)
        if await refreshCurrent() {
            errorMessage = originalMessage
        } else {
            selectedDetail = nil
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
