import CoreServices
import Foundation

final class PathMonitor: @unchecked Sendable {
    private let directory: URL
    private let relevant: @Sendable (String) -> Bool
    private let onChange: @MainActor () -> Void
    private var stream: FSEventStreamRef?
    private var debounceTimer: Timer?

    init(
        directory: URL,
        relevant: @escaping @Sendable (String) -> Bool,
        onChange: @escaping @MainActor () -> Void
    ) {
        self.directory = directory
        self.relevant = relevant
        self.onChange = onChange
    }

    deinit { stop() }

    @discardableResult
    func start() -> Bool {
        guard stream == nil else { return true }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return false
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &context,
            [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            flags
        ) else {
            return false
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            return false
        }
        self.stream = stream
        return true
    }

    func stop() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        self.stream = nil
    }

    private func receive(paths: [String]) {
        guard paths.contains(where: relevant) else { return }
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: 0.45,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self.debounceTimer = nil
            Task { @MainActor in self.onChange() }
        }
    }

    private static let callback: FSEventStreamCallback = {
        _, info, count, eventPaths, _, _ in
        guard let info,
              let paths = unsafeBitCast(eventPaths, to: NSArray.self)
                  as? [String]
        else {
            return
        }
        Unmanaged<PathMonitor>
            .fromOpaque(info)
            .takeUnretainedValue()
            .receive(paths: Array(paths.prefix(Int(count))))
    }
}
