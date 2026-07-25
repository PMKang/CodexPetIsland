import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let preferences = PetPreferences()
    private let store = PetDashboardStore()
    private var islandController: PetIslandController?
    private var statusItem: NSStatusItem?
    private var monitor: PathMonitor?
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        islandController = PetIslandController(
            store: store,
            preferences: preferences
        )
        configureStatusItem()
        configureMonitoring()
        store.refresh()

        preferences.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.rebuildMenu() }
            }
            .store(in: &cancellables)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        item.button?.image = NSImage(
            systemSymbolName: "pawprint.fill",
            accessibilityDescription: "Codex Pet Island"
        )
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuildMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        let show = NSMenuItem(
            title: text("Show Pet Island", "显示宠物岛"),
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        show.target = self
        show.state = preferences.isEnabled ? .on : .off
        menu.addItem(show)

        let follow = NSMenuItem(
            title: text("Follow Local Pet", "跟随本地宠物"),
            action: #selector(toggleFollow),
            keyEquivalent: ""
        )
        follow.target = self
        follow.state = preferences.followsLocalPet ? .on : .off
        menu.addItem(follow)

        if !preferences.pets.isEmpty {
            let petsItem = NSMenuItem(
                title: text("Pet", "宠物"),
                action: nil,
                keyEquivalent: ""
            )
            let submenu = NSMenu()
            for pet in preferences.pets {
                let item = NSMenuItem(
                    title: pet.displayName,
                    action: #selector(selectPet(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = pet.id
                item.state = pet.id == preferences.selectedPetID ? .on : .off
                submenu.addItem(item)
            }
            menu.setSubmenu(submenu, for: petsItem)
            menu.addItem(petsItem)
        }

        menu.addItem(.separator())
        let language = NSMenuItem(
            title: preferences.language == .chinese ? "EN" : "中",
            action: #selector(toggleLanguage),
            keyEquivalent: ""
        )
        language.target = self
        menu.addItem(language)

        let refresh = NSMenuItem(
            title: text("Refresh", "刷新"),
            action: #selector(refresh),
            keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: text("Quit", "退出"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    private func configureMonitoring() {
        let codexDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        let relevantPrefixes = [
            codexDirectory.appendingPathComponent("sessions").path,
            codexDirectory.appendingPathComponent("pets").path,
            codexDirectory.appendingPathComponent("config.toml").path,
            codexDirectory.appendingPathComponent("session_index.jsonl").path
        ]
        let monitor = PathMonitor(
            directory: codexDirectory,
            relevant: { path in
                relevantPrefixes.contains {
                    path == $0 || path.hasPrefix($0 + "/")
                }
            },
            onChange: { [weak self] in
                self?.preferences.reloadLocalPet()
                self?.store.refresh()
            }
        )
        _ = monitor.start()
        self.monitor = monitor

        let timer = Timer(timeInterval: 60, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.store.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func toggleEnabled() {
        preferences.isEnabled.toggle()
    }

    @objc private func toggleFollow() {
        preferences.setFollowsLocalPet(!preferences.followsLocalPet)
    }

    @objc private func selectPet(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        preferences.selectPet(id)
        preferences.isEnabled = true
    }

    @objc private func toggleLanguage() {
        preferences.language = preferences.language == .chinese
            ? .english
            : .chinese
    }

    @objc private func refresh() {
        preferences.reloadLocalPet()
        store.refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func text(_ english: String, _ chinese: String) -> String {
        preferences.language.text(english, chinese)
    }
}

@main
@MainActor
struct CodexPetIslandMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
