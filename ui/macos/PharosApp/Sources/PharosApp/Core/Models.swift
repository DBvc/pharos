import Foundation

enum SourceKind: String, Codable, CaseIterable {
    case manual
    case feishuChat = "feishu_chat"
    case feishuProject = "feishu_project"
    case gitlab
    case feishuDocs = "feishu_docs"

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .feishuChat: return "Feishu Chat"
        case .feishuProject: return "Feishu Project"
        case .gitlab: return "GitLab"
        case .feishuDocs: return "Feishu Docs"
        }
    }
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
        case .readyForReview: return "Ready For Review"
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

enum AttentionGroup: String, Codable {
    case needsDecision = "needs_decision"
    case needsInput = "needs_input"
    case watching
    case handled
    case noise

    var label: String {
        switch self {
        case .needsDecision: return "Needs Decision"
        case .needsInput: return "Needs Input"
        case .watching: return "Watching"
        case .handled: return "Handled"
        case .noise: return "Noise"
        }
    }
}

struct DecisionCard: Identifiable, Codable, Hashable {
    let requestId: String
    let title: String
    let summary: String
    let group: AttentionGroup
    let sourceKind: SourceKind
    let sourceUrl: String?
    let priority: Priority
    let risk: Risk
    let whyNow: String
    let preparedNextMove: String?
    let targetPreview: String?
    let evidenceCount: Int
    let updatedAt: String
    let debugStatus: RequestStatus

    var id: String { requestId }
}

struct NoiseSummary: Codable, Hashable {
    let count: Int
}

struct TodaySnapshot: Codable {
    let needsDecision: [DecisionCard]
    let needsInput: [DecisionCard]
    let watching: [DecisionCard]
    let handled: [DecisionCard]
    let noise: NoiseSummary
}

struct RequestDetail: Codable {
    let request: WorkRequest
    let actions: [ProposedAction]
    let evidence: [EvidenceItem]
    let timeline: [TimelineEvent]
}

struct SourceConfig: Identifiable, Codable, Hashable {
    let id: String
    let kind: SourceKind
    var enabled: Bool
    var readEnabled: Bool
    var writeEnabled: Bool
    var scopeJson: String
    let lastSyncAt: String?
    let lastError: String?
    let createdAt: String
    let updatedAt: String
}

struct SourcesResponse: Decodable {
    let sources: [SourceConfig]
}

struct SourceResponse: Decodable {
    let source: SourceConfig
}

struct SourcePatchPayload: Encodable {
    var enabled: Bool?
    var readEnabled: Bool?
    var writeEnabled: Bool?
    var scopeJson: String?
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
