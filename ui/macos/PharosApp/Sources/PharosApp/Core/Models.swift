import Foundation

enum SourceKind: String, Codable, CaseIterable {
    case manual
    case feishuChat = "feishu_chat"
    case feishuProject = "feishu_project"
    case gitlab
    case feishuDocs = "feishu_docs"
}

enum RequestStatus: String, Codable {
    case new
    case triaging
    case needsContext = "needs_context"
    case running
    case readyForReview = "ready_for_review"
    case waiting
    case approved
    case executing
    case done
    case failed
    case snoozed
    case archived

    var label: String {
        switch self {
        case .readyForReview: return "Needs Review"
        case .needsContext: return "Needs Context"
        default: return rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

enum Priority: String, Codable {
    case low
    case normal
    case high
    case urgent
}

enum Risk: String, Codable {
    case l0
    case l1
    case l2
    case l3
    case l4
    case l5

    var label: String { rawValue.uppercased() }
}

enum ActionStatus: String, Codable {
    case proposed
    case approved
    case rejected
    case executing
    case executed
    case failed
}

struct WorkRequest: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let summary: String
    let status: RequestStatus
    let priority: Priority
    let risk: Risk
    let sourceKind: SourceKind
    let sourceSignalId: String
    let reason: String
    let nextStep: String
    let createdAt: String
    let updatedAt: String
}

struct ProposedAction: Identifiable, Codable, Hashable {
    let id: String
    let requestId: String
    let title: String
    let body: String
    let targetKind: String
    let targetRef: String
    let risk: Risk
    let requiresApproval: Bool
    let status: ActionStatus
    let payloadHash: String
    let createdAt: String
    let updatedAt: String
}

struct EvidenceItem: Identifiable, Codable, Hashable {
    let id: String
    let requestId: String
    let kind: String
    let title: String
    let body: String
    let url: String?
    let createdAt: String
}

struct TimelineEvent: Identifiable, Codable, Hashable {
    let id: String
    let requestId: String
    let kind: String
    let title: String
    let body: String
    let createdAt: String
}

struct TodaySnapshot: Codable {
    let needsReview: [WorkRequest]
    let running: [WorkRequest]
    let needsContext: [WorkRequest]
    let newItems: [WorkRequest]
    let doneToday: [WorkRequest]
    let archivedNoiseCount: Int
}

struct RequestDetail: Codable {
    let request: WorkRequest
    let actions: [ProposedAction]
    let evidence: [EvidenceItem]
    let timeline: [TimelineEvent]
}

struct CapturePayload: Encodable {
    var title: String?
    var body: String
    var url: String?
    var actor: String?
}

struct CaptureResponse: Decodable {
    let request: WorkRequest
    let detailUrl: String
}

struct ApprovalResponse: Decodable {
    struct Approval: Decodable {
        let id: String
        let actionId: String
        let actionHash: String
        let decision: String
        let approvedBody: String?
        let createdAt: String
    }
    let approval: Approval
}

struct ActionResponse: Decodable {
    let action: ProposedAction
}

struct APIErrorResponse: Decodable, Error {
    let error: String
}
