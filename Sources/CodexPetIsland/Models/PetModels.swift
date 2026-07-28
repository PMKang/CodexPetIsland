import Foundation

struct CodexPet: Identifiable, Equatable, Sendable {
    let id: String
    let manifestID: String?
    let displayName: String
    let spriteVersionNumber: Int
    let spritesheetURL: URL
    let subagentFormURL: URL?
    let subagentScaleMultiplier: Double
    let manifestModifiedAt: Date

    var isCanonicalPackage: Bool {
        manifestID == nil || manifestID == id
    }
}

struct PetTask: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let project: String
    let totalTokens: Int64
    let updatedAt: Date
    let isRunning: Bool
    let isSubagent: Bool
}

struct QuotaSnapshot: Equatable, Sendable {
    let label: String
    let remainingPercent: Int
    let resetsAt: Date?
}

struct PetDashboardSnapshot: Equatable, Sendable {
    var quota: QuotaSnapshot?
    var tasks: [PetTask]
    var refreshedAt: Date

    var hasRunningTasks: Bool {
        tasks.contains(where: \.isRunning)
    }

    var hasRunningSubagents: Bool {
        tasks.contains { $0.isRunning && $0.isSubagent }
    }

    static let empty = PetDashboardSnapshot(
        quota: nil,
        tasks: [],
        refreshedAt: .distantPast
    )
}

enum AppLanguage: String, CaseIterable, Sendable {
    case chinese
    case english

    func text(_ english: String, _ chinese: String) -> String {
        self == .chinese ? chinese : english
    }
}
