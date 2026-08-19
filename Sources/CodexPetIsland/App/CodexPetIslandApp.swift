import AppKit
import Combine

final class ClipboardSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandPaste = modifiers == .command
            && event.charactersIgnoringModifiers?.lowercased() == "v"

        guard isCommandPaste else {
            return super.performKeyEquivalent(with: event)
        }

        guard let value = NSPasteboard.general.string(forType: .string) else {
            NSSound.beep()
            return true
        }

        let editor = currentEditor()
        let range = editor?.selectedRange
            ?? NSRange(location: stringValue.utf16.count, length: 0)
        stringValue = (stringValue as NSString).replacingCharacters(in: range, with: value)
        editor?.selectedRange = NSRange(
            location: range.location + value.utf16.count,
            length: 0
        )
        return true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let preferences = PetPreferences()
    private let store = PetDashboardStore()
    private var islandController: PetIslandController?
    private var statusItem: NSStatusItem?
    private var monitor: PathMonitor?
    private var openCodeMonitor: PathMonitor?
    private var localTimer: Timer?
    private var quotaTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var activeOpenCodeKeyPanel: NSPanel?
    private weak var activeOpenCodeKeyField: NSTextField?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).filter { $0.processIdentifier != currentPID }
        if let existing = otherInstances.first {
            existing.activate(options: [])
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        islandController = PetIslandController(
            store: store,
            preferences: preferences
        )
        configureStatusItem()
        configureMonitoring()
        store.refreshAll(forceQuota: true)

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

        let visibilityAction = NSMenuItem(
            title: preferences.isEnabled
                ? text("Hide Pet Island", "隐藏宠物岛")
                : text("Show Pet Island", "显示宠物岛"),
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        visibilityAction.target = self
        menu.addItem(visibilityAction)

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

        let configureGo = NSMenuItem(
            title: text("Configure OpenCode Go Key…", "配置 OpenCode Go Key…"),
            action: #selector(configureOpenCodeGo),
            keyEquivalent: ""
        )
        configureGo.target = self
        menu.addItem(configureGo)

        if OpenCodeGoKeychain.shared.read() != nil {
            let clearGo = NSMenuItem(
                title: text("Clear OpenCode Go Key", "清除 OpenCode Go Key"),
                action: #selector(clearOpenCodeGo),
                keyEquivalent: ""
            )
            clearGo.target = self
            menu.addItem(clearGo)
        }

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
                self?.store.refreshLocal()
            }
        )
        _ = monitor.start()
        self.monitor = monitor

        let openCodeDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode", isDirectory: true)
        let openCodeDatabase = openCodeDirectory
            .appendingPathComponent("opencode.db").path
        let openCodeMonitor = PathMonitor(
            directory: openCodeDirectory,
            relevant: { path in
                path == openCodeDatabase
                    || path.hasPrefix(openCodeDatabase + "-")
            },
            onChange: { [weak self] in self?.store.refreshLocal() }
        )
        _ = openCodeMonitor.start()
        self.openCodeMonitor = openCodeMonitor

        let localTimer = Timer(timeInterval: 60, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.store.refreshLocal() }
        }
        localTimer.tolerance = 10
        RunLoop.main.add(localTimer, forMode: .common)
        self.localTimer = localTimer

        let quotaTimer = Timer(timeInterval: 5 * 60, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.store.refreshQuota() }
        }
        quotaTimer.tolerance = 30
        RunLoop.main.add(quotaTimer, forMode: .common)
        self.quotaTimer = quotaTimer
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
        store.refreshAll(forceQuota: true)
    }

    @objc private func configureOpenCodeGo() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 230),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = text("Configure OpenCode Go", "配置 OpenCode Go")
        panel.isFloatingPanel = true
        panel.level = .modalPanel

        let content = NSView(frame: panel.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]
        panel.contentView = content

        let title = NSTextField(labelWithString: text("Configure OpenCode Go", "配置 OpenCode Go"))
        title.font = .boldSystemFont(ofSize: 18)
        title.frame = NSRect(x: 24, y: 178, width: 412, height: 24)

        let info = NSTextField(labelWithString: text(
            "The key is stored only in macOS Keychain and used for the official usage API.",
            "Key 只保存到 macOS 钥匙串，用于请求官方用量接口。"
        ))
        info.font = .systemFont(ofSize: 13)
        info.textColor = .secondaryLabelColor
        info.frame = NSRect(x: 24, y: 145, width: 412, height: 20)

        let field = ClipboardSecureTextField(frame: NSRect(x: 24, y: 100, width: 412, height: 28))
        field.placeholderString = text("Paste API key", "粘贴 API Key")
        field.stringValue = OpenCodeGoKeychain.shared.read() ?? ""

        let pasteButton = NSButton(
            title: text("Fill from Clipboard", "从剪贴板填入"),
            target: self,
            action: #selector(fillOpenCodeKeyFromClipboard)
        )
        pasteButton.bezelStyle = .rounded
        pasteButton.frame = NSRect(x: 24, y: 45, width: 150, height: 28)

        let cancelButton = NSButton(
            title: text("Cancel", "取消"),
            target: self,
            action: #selector(cancelOpenCodeKeyPanel)
        )
        cancelButton.bezelStyle = .rounded
        cancelButton.frame = NSRect(x: 300, y: 45, width: 80, height: 28)

        let saveButton = NSButton(
            title: text("Save", "保存"),
            target: self,
            action: #selector(saveOpenCodeKeyPanel)
        )
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: 380, y: 45, width: 56, height: 28)

        [title, info, field, pasteButton, cancelButton, saveButton].forEach(content.addSubview)
        activeOpenCodeKeyPanel = panel
        activeOpenCodeKeyField = field
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        activeOpenCodeKeyPanel = nil
        activeOpenCodeKeyField = nil
    }

    @objc private func saveOpenCodeKeyPanel() {
        guard let field = activeOpenCodeKeyField else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            NSSound.beep()
            return
        }
        do {
            try OpenCodeGoKeychain.shared.save(value)
            store.refreshQuota(force: true)
            NSApp.stopModal(withCode: .OK)
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func cancelOpenCodeKeyPanel() {
        NSApp.stopModal(withCode: .cancel)
    }

    @objc private func fillOpenCodeKeyFromClipboard() {
        guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else {
            NSSound.beep()
            return
        }
        activeOpenCodeKeyField?.stringValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        activeOpenCodeKeyField?.window?.makeFirstResponder(activeOpenCodeKeyField)
    }

    @objc private func clearOpenCodeGo() {
        OpenCodeGoKeychain.shared.delete()
        store.refreshQuota(force: true)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = text("Could not save OpenCode Go key", "保存 OpenCode Go Key 失败")
        alert.informativeText = message
        alert.runModal()
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
