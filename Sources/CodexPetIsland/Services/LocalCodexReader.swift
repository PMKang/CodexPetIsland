import Foundation

final class LocalCodexReader: @unchecked Sendable {
    private let sessionsDirectory: URL
    private let sessionIndexURL: URL
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    init(
        codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true),
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        sessionsDirectory = codexDirectory.appendingPathComponent(
            "sessions",
            isDirectory: true
        )
        sessionIndexURL = codexDirectory.appendingPathComponent(
            "session_index.jsonl"
        )
        self.fileManager = fileManager
        self.now = now
    }

    func read() -> PetDashboardSnapshot {
        let names = readSessionNames()
        let files = newestSessionFiles(limit: 12)
        var tasks: [PetTask] = []
        var newestQuota: (Date, QuotaSnapshot)?

        for file in files {
            guard let summary = summarize(file: file, names: names) else {
                continue
            }
            tasks.append(summary.task)
            if let (timestamp, quota) = summary.quota,
               newestQuota == nil || timestamp > newestQuota!.0 {
                newestQuota = (timestamp, quota)
            }
        }

        return PetDashboardSnapshot(
            quota: newestQuota?.1,
            tasks: Array(tasks.sorted { $0.updatedAt > $1.updatedAt }.prefix(8)),
            refreshedAt: now()
        )
    }

    private func newestSessionFiles(limit: Int) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .contentModificationDateKey]
            )
            guard values?.isRegularFile == true else { continue }
            files.append((url, values?.contentModificationDate ?? .distantPast))
        }
        return files.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    private func summarize(
        file: URL,
        names: [String: String]
    ) -> (task: PetTask, quota: (Date, QuotaSnapshot)?)? {
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: file.path
        ),
              let modifiedAt = attributes[.modificationDate] as? Date,
              let data = readTail(file, maximumBytes: 1_048_576),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        var sessionID: String?
        var workingDirectory: String?
        var latestTitle: String?
        var totalTokens: Int64 = 0
        var quota: (Date, QuotaSnapshot)?
        var lifecycleRunning: Bool?

        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any]
            else {
                continue
            }
            sessionID = sessionID ?? recursiveString(
                keys: ["session_id", "id"],
                in: dictionary,
                requiringParentType: "session_meta"
            )
            workingDirectory = workingDirectory
                ?? recursiveString(keys: ["cwd"], in: dictionary)
            if let title = extractUserText(dictionary), !title.isEmpty {
                latestTitle = title
            }
            if let tokens = recursiveNumber(
                keys: ["total_tokens"],
                in: dictionary
            ) {
                totalTokens = max(totalTokens, Int64(tokens))
            }
            if let candidate = extractQuota(dictionary) {
                let timestamp = eventTimestamp(dictionary) ?? modifiedAt
                if quota == nil || timestamp > quota!.0 {
                    quota = (timestamp, candidate)
                }
            }
            if let running = extractLifecycleRunning(dictionary) {
                lifecycleRunning = running
            }
        }

        let id = sessionID ?? file.deletingPathExtension().lastPathComponent
        let project = workingDirectory.map {
            URL(fileURLWithPath: $0).lastPathComponent
        } ?? "Codex"
        let title = names[id]
            ?? latestTitle?.singleLine(maximumLength: 44)
            ?? file.deletingPathExtension().lastPathComponent
        let running = lifecycleRunning
            ?? (now().timeIntervalSince(modifiedAt) <= 90)

        return (
            PetTask(
                id: id,
                title: title,
                project: project,
                totalTokens: totalTokens,
                updatedAt: modifiedAt,
                isRunning: running
            ),
            quota
        )
    }

    private func extractLifecycleRunning(
        _ dictionary: [String: Any]
    ) -> Bool? {
        guard dictionary["type"] as? String == "event_msg",
              let payload = dictionary["payload"] as? [String: Any],
              let type = payload["type"] as? String
        else {
            return nil
        }
        switch type {
        case "task_started":
            return true
        case "task_complete", "turn_aborted":
            return false
        default:
            return nil
        }
    }

    private func readTail(_ url: URL, maximumBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(maximumBytes)
            ? size - UInt64(maximumBytes)
            : 0
        try? handle.seek(toOffset: start)
        guard var data = try? handle.readToEnd() else { return nil }
        if start > 0, let newline = data.firstIndex(of: 0x0A) {
            data.removeSubrange(...newline)
        }
        return data
    }

    private func readSessionNames() -> [String: String] {
        guard let text = try? String(
            contentsOf: sessionIndexURL,
            encoding: .utf8
        ) else {
            return [:]
        }
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any],
                  let id = (dictionary["id"] ?? dictionary["session_id"]) as? String,
                  let name = (
                      dictionary["thread_name"]
                          ?? dictionary["title"]
                          ?? dictionary["name"]
                  ) as? String
            else {
                continue
            }
            result[id] = name
        }
        return result
    }

    private func extractUserText(_ dictionary: [String: Any]) -> String? {
        guard let payload = dictionary["payload"] as? [String: Any],
              let type = payload["type"] as? String,
              ["user_message", "user_input"].contains(type)
        else {
            return nil
        }
        return payload["message"] as? String
            ?? payload["text"] as? String
    }

    private func extractQuota(_ dictionary: [String: Any]) -> QuotaSnapshot? {
        guard let limits = findDictionary(named: "rate_limits", in: dictionary)
        else {
            return nil
        }
        let windows = ["secondary", "primary"].compactMap {
            limits[$0] as? [String: Any]
        }
        let weekly = windows.first(where: {
            ($0["window_minutes"] as? NSNumber)?.doubleValue ?? 0 >= 1_440
        }) ?? windows.first
        guard let weekly,
              let used = (weekly["used_percent"] as? NSNumber)?.doubleValue
        else {
            return nil
        }
        let resetSeconds = (weekly["resets_at"] as? NSNumber)?.doubleValue
        let resetDate = resetSeconds.map(Date.init(timeIntervalSince1970:))
        return QuotaSnapshot(
            label: "7d",
            remainingPercent: min(100, max(0, Int((100 - used).rounded()))),
            resetsAt: resetDate
        )
    }

    private func eventTimestamp(_ dictionary: [String: Any]) -> Date? {
        guard let raw = dictionary["timestamp"] as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        if let date = fractional.date(from: raw) {
            return date
        }
        return ISO8601DateFormatter().date(from: raw)
    }

    private func findDictionary(
        named key: String,
        in value: Any
    ) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            if let result = dictionary[key] as? [String: Any] {
                return result
            }
            for nested in dictionary.values {
                if let result = findDictionary(named: key, in: nested) {
                    return result
                }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let result = findDictionary(named: key, in: nested) {
                    return result
                }
            }
        }
        return nil
    }

    private func recursiveString(
        keys: Set<String>,
        in value: Any,
        requiringParentType parentType: String? = nil
    ) -> String? {
        if let dictionary = value as? [String: Any] {
            let matchesParent = parentType == nil
                || dictionary["type"] as? String == parentType
            if matchesParent {
                for key in keys {
                    if let result = dictionary[key] as? String {
                        return result
                    }
                }
            }
            for nested in dictionary.values {
                if let result = recursiveString(
                    keys: keys,
                    in: nested,
                    requiringParentType: parentType
                ) {
                    return result
                }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let result = recursiveString(
                    keys: keys,
                    in: nested,
                    requiringParentType: parentType
                ) {
                    return result
                }
            }
        }
        return nil
    }

    private func recursiveNumber(keys: Set<String>, in value: Any) -> Double? {
        if let dictionary = value as? [String: Any] {
            for key in keys {
                if let number = dictionary[key] as? NSNumber {
                    return number.doubleValue
                }
            }
            for nested in dictionary.values {
                if let result = recursiveNumber(keys: keys, in: nested) {
                    return result
                }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let result = recursiveNumber(keys: keys, in: nested) {
                    return result
                }
            }
        }
        return nil
    }
}

private extension String {
    func singleLine(maximumLength: Int) -> String {
        let line = replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.count > maximumLength else { return line }
        return String(line.prefix(maximumLength - 1)) + "…"
    }
}
