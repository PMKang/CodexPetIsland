import Foundation

final class OpenCodeSessionReader: @unchecked Sendable {
    private let databaseURL: URL
    private let now: @Sendable () -> Date
    private let sqliteURL: URL

    init(
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/opencode.db"),
        sqliteURL: URL = URL(fileURLWithPath: "/usr/bin/sqlite3"),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.databaseURL = databaseURL
        self.sqliteURL = sqliteURL
        self.now = now
    }

    func readTasks() -> [PetTask] {
        guard FileManager.default.fileExists(atPath: databaseURL.path),
              FileManager.default.isExecutableFile(atPath: sqliteURL.path)
        else {
            return []
        }
        let query = """
        SELECT id,
               replace(replace(title, char(9), ' '), char(10), ' '),
               directory,
               time_updated,
               cost
        FROM session
        ORDER BY time_updated DESC
        LIMIT 8;
        """
        guard let output = runSQLite(query), !output.isEmpty else { return [] }
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 5,
                  let milliseconds = Double(fields[3])
            else { return nil }
            let updatedAt = Date(timeIntervalSince1970: milliseconds / 1000)
            let title = String(fields[1]).singleLine(maximumLength: 44)
            let directory = String(fields[2])
            let project = URL(fileURLWithPath: directory).lastPathComponent
            let cost = Double(fields[4]) ?? 0
            return PetTask(
                id: String(fields[0]),
                source: .openCodeGo,
                title: title.isEmpty ? "OpenCode Go" : title,
                project: project.isEmpty ? "OpenCode Go" : project,
                totalTokens: Int64(max(0, cost * 1_000_000)),
                updatedAt: updatedAt,
                isRunning: now().timeIntervalSince(updatedAt) <= 90,
                isSubagent: false
            )
        }
    }

    private func runSQLite(_ query: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = sqliteURL
        process.arguments = ["-readonly", "-separator", "\t", databaseURL.path, query]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0,
              let data = try? output.fileHandleForReading.readToEnd()
        else { return nil }
        return String(data: data, encoding: .utf8)
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
