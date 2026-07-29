import Foundation

protocol CodexQuotaFetching: Sendable {
    func fetchQuota() throws -> QuotaSnapshot
}

enum CodexQuotaError: LocalizedError, Equatable {
    case executableNotFound
    case launchFailed(String)
    case timedOut
    case server(String)
    case missingRateLimits
    case missingWeeklyWindow

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Codex executable not found"
        case let .launchFailed(message):
            "Codex app-server launch failed: \(message)"
        case .timedOut:
            "Codex app-server quota request timed out"
        case let .server(message):
            "Codex app-server quota request failed: \(message)"
        case .missingRateLimits:
            "Codex app-server returned no main rate limits"
        case .missingWeeklyWindow:
            "Codex app-server returned no weekly quota window"
        }
    }
}

final class CodexAppServerQuotaClient:
    CodexQuotaFetching,
    @unchecked Sendable
{
    private let executableURL: URL?
    private let timeout: TimeInterval

    convenience init(timeout: TimeInterval = 8) {
        self.init(
            executableURL: Self.findCodexExecutable(),
            timeout: timeout
        )
    }

    init(
        executableURL: URL?,
        timeout: TimeInterval = 8
    ) {
        self.executableURL = executableURL
        self.timeout = max(2, timeout)
    }

    func fetchQuota() throws -> QuotaSnapshot {
        guard let executableURL else {
            throw CodexQuotaError.executableNotFound
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let response = AppServerResponseBuffer()
        output.fileHandleForReading.readabilityHandler = { handle in
            response.consume(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw CodexQuotaError.launchFailed(error.localizedDescription)
        }

        do {
            for message in Self.requestMessages() {
                var data = try JSONSerialization.data(withJSONObject: message)
                data.append(0x0A)
                try input.fileHandleForWriting.write(contentsOf: data)
            }
        } catch {
            finish(process: process, input: input, output: output)
            throw CodexQuotaError.server(error.localizedDescription)
        }

        let waitResult = response.completed.wait(timeout: .now() + timeout)
        finish(process: process, input: input, output: output)

        guard waitResult == .success else {
            throw CodexQuotaError.timedOut
        }
        let resolved = response.resolved()
        if let message = resolved.serverError {
            throw CodexQuotaError.server(message)
        }
        guard let result = resolved.result else {
            throw CodexQuotaError.missingRateLimits
        }
        return try Self.parseRateLimitsResponse(result)
    }

    static func requestMessages() -> [[String: Any]] {
        [
            [
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "codex_pet_island",
                        "title": "Codex Pet Island",
                        "version": "1"
                    ]
                ]
            ],
            ["method": "initialized"],
            ["id": 2, "method": "account/rateLimits/read"]
        ]
    }

    static func parseRateLimitsResponse(
        _ result: [String: Any]
    ) throws -> QuotaSnapshot {
        let selected: [String: Any]?
        if let byID = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = byID["codex"] as? [String: Any] {
            selected = codex
        } else if let limits = result["rateLimits"] as? [String: Any],
                  limits["limitId"] as? String == nil
                    || limits["limitId"] as? String == "codex" {
            selected = limits
        } else {
            selected = nil
        }

        guard let selected else {
            throw CodexQuotaError.missingRateLimits
        }

        let windows = ["primary", "secondary"].compactMap {
            parseWindow(selected[$0])
        }
        let weeklyMatches = windows.filter {
            $0.durationMinutes.map { $0 >= 1_440 } ?? false
        }
        let weekly: ParsedRateWindow?
        if weeklyMatches.count == 1 {
            weekly = weeklyMatches[0]
        } else if weeklyMatches.isEmpty, windows.count == 1 {
            weekly = windows[0]
        } else {
            weekly = nil
        }
        guard let weekly else {
            throw CodexQuotaError.missingWeeklyWindow
        }

        let durationDays = weekly.durationMinutes.map {
            max(1, Int(($0 / 1_440).rounded()))
        } ?? 7
        let reset = weekly.resetsAt.flatMap {
            $0.timeIntervalSince1970 > 0 ? $0 : nil
        }
        return QuotaSnapshot(
            label: "\(durationDays)d",
            remainingPercent: min(
                100,
                max(0, Int((100 - weekly.usedPercent).rounded()))
            ),
            resetsAt: reset
        )
    }

    static func findCodexExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [String] = []
        if let configured = environment["CODEX_PET_ISLAND_CODEX_BINARY"],
           !configured.isEmpty {
            candidates.append(
                NSString(string: configured).expandingTildeInPath
            )
        }
        candidates.append(contentsOf: [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            homeDirectory.appendingPathComponent(
                "Applications/ChatGPT.app/Contents/Resources/codex"
            ).path,
            homeDirectory.appendingPathComponent(
                "Applications/Codex.app/Contents/Resources/codex"
            ).path
        ])
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0))
                    .appendingPathComponent("codex").path
            })
        }
        return candidates.first(where: fileManager.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }

    private func finish(process: Process, input: Pipe, output: Pipe) {
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
    }

    private struct ParsedRateWindow {
        let usedPercent: Double
        let durationMinutes: Double?
        let resetsAt: Date?
    }

    private static func parseWindow(_ value: Any?) -> ParsedRateWindow? {
        guard let dictionary = value as? [String: Any],
              let used = number(dictionary["usedPercent"]
                ?? dictionary["used_percent"]),
              used.isFinite,
              (0 ... 100).contains(used)
        else {
            return nil
        }
        let minutes = number(
            dictionary["windowDurationMins"]
                ?? dictionary["window_minutes"]
        )
        let reset = number(dictionary["resetsAt"] ?? dictionary["resets_at"])
            .map(Date.init(timeIntervalSince1970:))
        return ParsedRateWindow(
            usedPercent: used,
            durationMinutes: minutes,
            resetsAt: reset
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }
}

private final class AppServerResponseBuffer: @unchecked Sendable {
    let completed = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var pending = Data()
    private var didComplete = false
    private(set) var result: [String: Any]?
    private(set) var serverError: String?

    func resolved() -> (
        result: [String: Any]?,
        serverError: String?
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (result, serverError)
    }

    func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[..<newline]
            pending.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line)
                    as? [String: Any],
                  (object["id"] as? NSNumber)?.intValue == 2
            else {
                continue
            }
            if let error = object["error"] as? [String: Any] {
                serverError = error["message"] as? String ?? "Unknown error"
            } else {
                result = object["result"] as? [String: Any]
            }
            if !didComplete {
                didComplete = true
                completed.signal()
            }
        }
    }
}
