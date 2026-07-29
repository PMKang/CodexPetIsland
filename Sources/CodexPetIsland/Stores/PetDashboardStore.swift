import Foundation

@MainActor
final class PetDashboardStore: ObservableObject {
    @Published private(set) var snapshot = PetDashboardSnapshot.empty
    @Published private(set) var quotaError: String?

    private let localReader: LocalCodexReader
    private let quotaClient: any CodexQuotaFetching
    private let now: @Sendable () -> Date
    private var localRefreshTask: Task<Void, Never>?
    private var quotaRefreshTask: Task<Void, Never>?
    private var lastQuotaAttemptAt: Date?

    init(
        reader: LocalCodexReader = LocalCodexReader(),
        quotaClient: any CodexQuotaFetching = CodexAppServerQuotaClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        localReader = reader
        self.quotaClient = quotaClient
        self.now = now
    }

    func refreshLocal() {
        guard localRefreshTask == nil else { return }
        localRefreshTask = Task { [weak self, localReader] in
            let snapshot = await Task.detached(priority: .utility) {
                localReader.read()
            }.value
            guard let self else { return }
            var updated = snapshot
            updated.quota = self.snapshot.quota
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
        quotaRefreshTask = Task { [weak self, quotaClient] in
            let result = await Task.detached(priority: .utility) {
                Result { try quotaClient.fetchQuota() }
            }.value
            guard let self else { return }
            switch result {
            case let .success(quota):
                self.quotaError = nil
                var updated = self.snapshot
                updated.quota = quota
                updated.refreshedAt = self.now()
                self.snapshot = updated
            case let .failure(error):
                self.quotaError = error.localizedDescription
            }
            self.quotaRefreshTask = nil
        }
    }

    func refreshAll(forceQuota: Bool = false) {
        refreshLocal()
        refreshQuota(force: forceQuota)
    }
}
