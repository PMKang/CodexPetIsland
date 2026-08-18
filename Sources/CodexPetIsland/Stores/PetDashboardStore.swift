import Foundation

@MainActor
final class PetDashboardStore: ObservableObject {
    @Published private(set) var snapshot = PetDashboardSnapshot.empty
    @Published private(set) var quotaError: String?

    private let localReader: LocalCodexReader
    private let openCodeReader: OpenCodeSessionReader
    private let codexQuotaClient: any CodexQuotaFetching
    private let openCodeGoQuotaClient: any OpenCodeGoQuotaFetching
    private let now: @Sendable () -> Date
    private var localRefreshTask: Task<Void, Never>?
    private var quotaRefreshTask: Task<Void, Never>?
    private var lastQuotaAttemptAt: Date?

    init(
        reader: LocalCodexReader = LocalCodexReader(),
        openCodeReader: OpenCodeSessionReader = OpenCodeSessionReader(),
        codexQuotaClient: any CodexQuotaFetching = CodexAppServerQuotaClient(),
        openCodeGoQuotaClient: any OpenCodeGoQuotaFetching = OpenCodeGoQuotaClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        localReader = reader
        self.openCodeReader = openCodeReader
        self.codexQuotaClient = codexQuotaClient
        self.openCodeGoQuotaClient = openCodeGoQuotaClient
        self.now = now
    }

    func refreshLocal() {
        guard localRefreshTask == nil else { return }
        localRefreshTask = Task { [weak self, localReader, openCodeReader] in
            let result = await Task.detached(priority: .utility) {
                (localReader.read(), openCodeReader.readTasks())
            }.value
            guard let self else { return }
            let (codexSnapshot, openCodeTasks) = result
            var updated = codexSnapshot
            updated.tasks = (codexSnapshot.tasks + openCodeTasks)
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(8)
                .map { $0 }
            updated.quota = self.snapshot.quota
            updated.openCodeGoQuota = self.snapshot.openCodeGoQuota
            self.snapshot = updated
            self.localRefreshTask = nil
        }
    }

    func refreshQuota(
        force: Bool = false,
        minimumInterval: TimeInterval = 5 * 60
    ) {
        guard quotaRefreshTask == nil else { return }
        let currentTime = now()
        if !force,
           let lastQuotaAttemptAt,
           currentTime.timeIntervalSince(lastQuotaAttemptAt) < minimumInterval {
            return
        }
        lastQuotaAttemptAt = currentTime
        quotaRefreshTask = Task { [weak self, codexQuotaClient, openCodeGoQuotaClient] in
            let result = await Task.detached(priority: .utility) {
                let codex = Result { try codexQuotaClient.fetchQuota() }
                let openCodeGo: Result<OpenCodeGoQuotaSnapshot, Error>
                do {
                    openCodeGo = .success(
                        try await openCodeGoQuotaClient.fetchQuota()
                    )
                } catch {
                    openCodeGo = .failure(error)
                }
                return (codex, openCodeGo)
            }.value
            guard let self else { return }
            var updated = self.snapshot
            var errors: [String] = []
            switch result.0 {
            case let .success(quota): updated.quota = quota
            case let .failure(error): errors.append(error.localizedDescription)
            }
            switch result.1 {
            case let .success(quota): updated.openCodeGoQuota = quota
            case let .failure(error):
                if let quotaError = error as? OpenCodeGoQuotaError,
                   quotaError == .keyMissing {
                    break
                } else {
                    errors.append(error.localizedDescription)
                }
            }
            updated.refreshedAt = self.now()
            self.snapshot = updated
            self.quotaError = errors.isEmpty ? nil : errors.joined(separator: "\n")
            self.quotaRefreshTask = nil
        }
    }

    func refreshAll(forceQuota: Bool = false) {
        refreshLocal()
        refreshQuota(force: forceQuota)
    }
}
