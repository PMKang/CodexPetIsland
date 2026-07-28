import Foundation

@MainActor
final class PetDashboardStore: ObservableObject {
    @Published private(set) var snapshot = PetDashboardSnapshot.empty
    @Published private(set) var quotaError: String?

    private let localReader: LocalCodexReader
    private let quotaClient: any CodexQuotaFetching
    private let quotaCache: CodexQuotaCache
    private let now: @Sendable () -> Date
    private var localRefreshTask: Task<Void, Never>?
    private var quotaRefreshTask: Task<Void, Never>?
    private var lastQuotaAttemptAt: Date?
    private var lastOfficialQuota: QuotaSnapshot?

    init(
        reader: LocalCodexReader = LocalCodexReader(),
        quotaClient: any CodexQuotaFetching = CodexAppServerQuotaClient(),
        quotaCache: CodexQuotaCache = CodexQuotaCache(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        localReader = reader
        self.quotaClient = quotaClient
        self.quotaCache = quotaCache
        self.now = now
        lastOfficialQuota = quotaCache.load(now: now())
        if let lastOfficialQuota {
            snapshot.quota = lastOfficialQuota
        }
    }

    func refreshLocal() {
        guard localRefreshTask == nil else { return }
        localRefreshTask = Task { [weak self, localReader] in
            let snapshot = await Task.detached(priority: .utility) {
                localReader.read()
            }.value
            guard let self else { return }
            var merged = snapshot
            merged.quota = Self.preferredQuota(
                official: self.validOfficialQuota(),
                local: snapshot.quota
            )
            self.snapshot = merged
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
        quotaRefreshTask = Task {
            [weak self, quotaClient, quotaCache] in
            let result = await Task.detached(priority: .utility) {
                Result { try quotaClient.fetchQuota() }
            }.value
            guard let self else { return }
            switch result {
            case let .success(quota):
                self.lastOfficialQuota = quota
                self.quotaError = nil
                quotaCache.save(quota)
                var updated = self.snapshot
                updated.quota = quota
                updated.refreshedAt = self.now()
                self.snapshot = updated
            case let .failure(error):
                self.quotaError = error.localizedDescription
                if self.snapshot.quota == nil,
                   let cached = quotaCache.load(now: self.now()) {
                    self.lastOfficialQuota = cached
                    var updated = self.snapshot
                    updated.quota = cached
                    self.snapshot = updated
                }
            }
            self.quotaRefreshTask = nil
        }
    }

    func refreshAll(forceQuota: Bool = false) {
        refreshLocal()
        refreshQuota(force: forceQuota)
    }

    private func validOfficialQuota() -> QuotaSnapshot? {
        guard let quota = lastOfficialQuota else { return nil }
        if let reset = quota.resetsAt, reset <= now() {
            lastOfficialQuota = nil
            return nil
        }
        return quota
    }

    static func preferredQuota(
        official: QuotaSnapshot?,
        local: QuotaSnapshot?
    ) -> QuotaSnapshot? {
        switch (official, local) {
        case let (official?, local?):
            if official.fetchedAt == local.fetchedAt {
                return official
            }
            return official.fetchedAt > local.fetchedAt ? official : local
        case let (official?, nil):
            return official
        case let (nil, local?):
            return local
        case (nil, nil):
            return nil
        }
    }
}
