import Foundation

struct CodexPet: Identifiable, Equatable, Sendable {
    let id: String
    let manifestID: String?
    let displayName: String
    let spriteVersionNumber: Int
    let spritesheetURL: URL
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
