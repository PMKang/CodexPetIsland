import Foundation

@MainActor
final class PetDashboardStore: ObservableObject {
    @Published private(set) var snapshot = PetDashboardSnapshot.empty
    private let reader: LocalCodexReader
    private var refreshTask: Task<Void, Never>?

    init(reader: LocalCodexReader = LocalCodexReader()) {
        self.reader = reader
    }

    func refresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self, reader] in
            let snapshot = await Task.detached(priority: .utility) {
                reader.read()
            }.value
            guard let self else { return }
            self.snapshot = snapshot
            self.refreshTask = nil
        }
    }
}
