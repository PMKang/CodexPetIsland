import Foundation

@MainActor
final class PetPreferences: ObservableObject {
    static let scaleRange = 75.0 ... 300.0
    static let defaultScale = 100.0

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }
    @Published var scalePercent: Double {
        didSet { defaults.set(scalePercent, forKey: Keys.scale) }
    }
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }
    @Published private(set) var followsLocalPet: Bool
    @Published private(set) var pets: [CodexPet]
    @Published var selectedPetID: String {
        didSet { defaults.set(selectedPetID, forKey: Keys.selectedPet) }
    }

    private let defaults: UserDefaults
    private var localSelectedPetID: String?

    init(
        pets: [CodexPet] = CodexPetCatalog().load(),
        localSelectedPetID: String? = CodexPetSelectionReader().selectedPetID(),
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.pets = pets
        self.localSelectedPetID = localSelectedPetID
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        let storedScale = defaults.object(forKey: Keys.scale) as? Double
            ?? Self.defaultScale
        scalePercent = min(
            Self.scaleRange.upperBound,
            max(Self.scaleRange.lowerBound, storedScale)
        )
        language = defaults.string(forKey: Keys.language)
            .flatMap(AppLanguage.init(rawValue:)) ?? .chinese
        let explicit = defaults.bool(forKey: Keys.explicitPet)
        followsLocalPet = !explicit
        if explicit,
           let saved = defaults.string(forKey: Keys.selectedPet),
           pets.contains(where: { $0.id == saved }) {
            selectedPetID = saved
        } else {
            selectedPetID = Self.recommendedPet(
                pets,
                selectedID: localSelectedPetID
            )?.id ?? ""
        }
    }

    var selectedPet: CodexPet? {
        pets.first(where: { $0.id == selectedPetID }) ?? pets.first
    }

    func setFollowsLocalPet(_ follows: Bool) {
        defaults.set(!follows, forKey: Keys.explicitPet)
        followsLocalPet = follows
        if follows {
            selectedPetID = Self.recommendedPet(
                pets,
                selectedID: localSelectedPetID
            )?.id ?? ""
        }
    }

    func selectPet(_ id: String) {
        guard pets.contains(where: { $0.id == id }) else { return }
        defaults.set(true, forKey: Keys.explicitPet)
        followsLocalPet = false
        selectedPetID = id
    }

    func reloadLocalPet() {
        pets = CodexPetCatalog().load()
        localSelectedPetID = CodexPetSelectionReader().selectedPetID()
        if followsLocalPet {
            selectedPetID = Self.recommendedPet(
                pets,
                selectedID: localSelectedPetID
            )?.id ?? ""
        }
    }

    private static func recommendedPet(
        _ pets: [CodexPet],
        selectedID: String?
    ) -> CodexPet? {
        if let selectedID,
           let pet = pets.first(where: { $0.id == selectedID })
                ?? pets.first(where: {
                    $0.manifestID == selectedID && $0.isCanonicalPackage
                }) {
            return pet
        }
        let canonical = pets.filter(\.isCanonicalPackage)
        return (canonical.isEmpty ? pets : canonical).max {
            $0.manifestModifiedAt < $1.manifestModifiedAt
        }
    }

    private enum Keys {
        static let enabled = "petIsland.enabled"
        static let scale = "petIsland.scalePercent"
        static let language = "petIsland.language"
        static let selectedPet = "petIsland.selectedPetID"
        static let explicitPet = "petIsland.explicitPet"
    }
}
