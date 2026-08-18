import Foundation
import Security

protocol OpenCodeGoQuotaFetching: Sendable {
    func fetchQuota() async throws -> OpenCodeGoQuotaSnapshot
}

enum OpenCodeGoQuotaError: LocalizedError, Equatable {
    case keyMissing
    case unauthorized
    case server(Int)
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .keyMissing:
            "OpenCode Go API key is not configured"
        case .unauthorized:
            "OpenCode Go API key is invalid or the subscription is unavailable"
        case let .server(status):
            "OpenCode Go usage request failed (HTTP \(status))"
        case .invalidResponse:
            "OpenCode Go returned an invalid usage response"
        case let .requestFailed(message):
            "OpenCode Go request failed: \(message)"
        }
    }
}

final class OpenCodeGoKeychain: @unchecked Sendable {
    static let shared = OpenCodeGoKeychain()

    private let service = "com.pmkang.CodexPetIsland"
    private let account = "opencode-go-api-key"

    func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }

    func save(_ value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw OpenCodeGoKeychainError.status(addStatus)
            }
        } else if status != errSecSuccess {
            throw OpenCodeGoKeychainError.status(status)
        }
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum OpenCodeGoKeychainError: LocalizedError, Equatable {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .status(status):
            "Could not save OpenCode Go API key (Keychain status \(status))"
        }
    }
}

final class OpenCodeGoQuotaClient: OpenCodeGoQuotaFetching, @unchecked Sendable {
    static let endpoint = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    private let keychain: OpenCodeGoKeychain
    private let session: URLSession

    init(
        keychain: OpenCodeGoKeychain = .shared,
        session: URLSession = .shared
    ) {
        self.keychain = keychain
        self.session = session
    }

    func fetchQuota() async throws -> OpenCodeGoQuotaSnapshot {
        guard let key = keychain.read() else {
            throw OpenCodeGoQuotaError.keyMissing
        }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenCodeGoQuotaError.requestFailed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw OpenCodeGoQuotaError.invalidResponse
        }
        switch http.statusCode {
        case 200 ... 299:
            return try Self.parse(data: data)
        case 401, 403:
            throw OpenCodeGoQuotaError.unauthorized
        default:
            throw OpenCodeGoQuotaError.server(http.statusCode)
        }
    }

    static func parse(data: Data) throws -> OpenCodeGoQuotaSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = object["usage"] as? [String: Any]
        else {
            throw OpenCodeGoQuotaError.invalidResponse
        }
        return OpenCodeGoQuotaSnapshot(
            rolling: parseWindow(usage["rolling"]),
            weekly: parseWindow(usage["weekly"])
        )
    }

    private static func parseWindow(_ value: Any?) -> QuotaWindow? {
        guard let dictionary = value as? [String: Any],
              let percent = number(dictionary["percent"]),
              percent.isFinite,
              (0 ... 100).contains(percent)
        else {
            return nil
        }
        let reset = (dictionary["resetsAt"] as? String).flatMap {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: $0)
                ?? ISO8601DateFormatter().date(from: $0)
        }
        return QuotaWindow(
            usedPercent: Int(percent.rounded()),
            resetsAt: reset
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
