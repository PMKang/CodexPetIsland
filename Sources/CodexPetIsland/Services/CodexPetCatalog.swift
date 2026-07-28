import Foundation

struct CodexPetCatalog {
    let roots: [URL]
    private let fileManager: FileManager

    init(
        roots: [URL] = Self.defaultRoots(),
        fileManager: FileManager = .default
    ) {
        self.roots = roots
        self.fileManager = fileManager
    }

    func load() -> [CodexPet] {
        var seenIDs: Set<String> = []
        var pets: [CodexPet] = []

        for root in roots {
            guard let directories = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for directory in directories.sorted(by: {
                $0.lastPathComponent < $1.lastPathComponent
            }) {
                guard let pet = loadPet(in: directory),
                      seenIDs.insert(pet.id).inserted
                else {
                    continue
                }
                pets.append(pet)
            }
        }

        return pets.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                == .orderedAscending
        }
    }

    static func defaultRoots(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            homeDirectory.appendingPathComponent(".codex/pets", isDirectory: true),
            homeDirectory.appendingPathComponent(
                "Library/Application Support/Codex/pets",
                isDirectory: true
            ),
            homeDirectory.appendingPathComponent(
                "Library/Application Support/ChatGPT/pets",
                isDirectory: true
            )
        ]
    }

    private func loadPet(in directory: URL) -> CodexPet? {
        let manifestURL = directory.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(
                  CodexPetManifest.self,
                  from: data
              )
        else {
            return nil
        }

        let directoryURL = directory.standardizedFileURL
        let spriteURL = directoryURL
            .appendingPathComponent(manifest.spritesheetPath)
            .standardizedFileURL
        guard spriteURL.path.hasPrefix(directoryURL.path + "/"),
              fileManager.fileExists(atPath: spriteURL.path)
        else {
            return nil
        }
        let subagentFormURL: URL? = manifest.subagentFormPath.flatMap {
            let url = directoryURL
                .appendingPathComponent($0)
                .standardizedFileURL
            guard url.path.hasPrefix(directoryURL.path + "/"),
                  fileManager.fileExists(atPath: url.path)
            else {
                return nil
            }
            return url
        }
        let modifiedAt = (try? manifestURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate) ?? .distantPast
        return CodexPet(
            id: directory.lastPathComponent,
            manifestID: manifest.id?.trimmedNonEmpty,
            displayName: manifest.displayName?.trimmedNonEmpty
                ?? directory.lastPathComponent,
            spriteVersionNumber: manifest.spriteVersionNumber,
            spritesheetURL: spriteURL,
            subagentFormURL: subagentFormURL,
            subagentScaleMultiplier: min(
                3,
                max(1, manifest.subagentScaleMultiplier ?? 1.5)
            ),
            manifestModifiedAt: modifiedAt
        )
    }
}

private struct CodexPetManifest: Decodable {
    let id: String?
    let displayName: String?
    let spriteVersionNumber: Int
    let spritesheetPath: String
    let subagentFormPath: String?
    let subagentScaleMultiplier: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case spriteVersionNumber
        case spritesheetPath
        case subagentFormPath
        case subagentScaleMultiplier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(
            String.self,
            forKey: .displayName
        )
        spriteVersionNumber = try container.decodeIfPresent(
            Int.self,
            forKey: .spriteVersionNumber
        ) ?? 1
        spritesheetPath = try container.decodeIfPresent(
            String.self,
            forKey: .spritesheetPath
        ) ?? "spritesheet.webp"
        subagentFormPath = try container.decodeIfPresent(
            String.self,
            forKey: .subagentFormPath
        )
        subagentScaleMultiplier = try container.decodeIfPresent(
            Double.self,
            forKey: .subagentScaleMultiplier
        )
    }
}

struct CodexPetSelectionReader {
    let configURL: URL

    init(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")
    ) {
        self.configURL = configURL
    }

    func selectedPetID() -> String? {
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8)
        else {
            return nil
        }
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("selected-avatar-id"),
                  let separator = line.firstIndex(of: "=")
            else {
                continue
            }
            var value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            if let comment = value.firstIndex(of: "#") {
                value = String(value[..<comment])
                    .trimmingCharacters(in: .whitespaces)
            }
            value = value.trimmingCharacters(
                in: CharacterSet(charactersIn: "\"'")
            )
            return value.split(separator: ":", maxSplits: 1)
                .last
                .map(String.init)
        }
        return nil
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let result = trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
