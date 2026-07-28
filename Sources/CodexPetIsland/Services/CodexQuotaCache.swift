import Foundation

struct CodexQuotaCache: @unchecked Sendable {
    let url: URL
    private let fileManager: FileManager

    init(
        url: URL = Self.defaultURL(),
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.fileManager = fileManager
    }

    func load(now: Date = Date()) -> QuotaSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(
                  QuotaSnapshot.self,
                  from: data
              ),
              now.timeIntervalSince(cached.fetchedAt) <= 86_400
        else {
            return nil
        }
        if let reset = cached.resetsAt, reset <= now {
            return nil
        }
        return cached.withSource(.cache)
    }

    func save(_ quota: QuotaSnapshot) {
        guard quota.source == .appServer,
              let data = try? JSONEncoder().encode(quota)
        else {
            return
        }
        let directory = url.deletingLastPathComponent()
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    static func defaultURL(
        fileManager: FileManager = .default
    ) -> URL {
        let base = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("CodexPetIsland", isDirectory: true)
            .appendingPathComponent("quota.json")
    }
}
