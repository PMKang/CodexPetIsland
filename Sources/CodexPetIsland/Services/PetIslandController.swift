import AppKit
import Combine
import SwiftUI

enum PetDockEdge: Equatable {
    case left
    case right
}

struct PetIslandPlacement {
    static let baseFloating = NSSize(width: 324, height: 132)
    static let baseExpanded = NSSize(width: 410, height: 380)
    static let baseDocked = NSSize(width: 104, height: 112)

    static func petControlSize(scale: CGFloat) -> CGFloat {
        78 * scale
    }

    static func size(
        expanded: Bool,
        docked: Bool,
        scale: CGFloat
    ) -> NSSize {
        if docked {
            return NSSize(
                width: baseDocked.width * scale,
                height: baseDocked.height * scale
            )
        }
        if expanded {
            return NSSize(
                width: baseExpanded.width,
                height: max(
                    baseExpanded.height,
                    petControlSize(scale: scale) + 302
                )
            )
        }
        return NSSize(
            width: baseFloating.width,
            height: max(
                baseFloating.height,
                petControlSize(scale: scale) + 54
            )
        )
    }
}

@MainActor
final class PetIslandController: NSObject {
    private let panel: NSPanel
    private let store: PetDashboardStore
    private let preferences: PetPreferences
    private var expanded = false
    private var dockEdge: PetDockEdge?
    private var direction: PetDockEdge = .right
    private var origin: NSPoint?
    private var screenNumber: NSNumber?
    private var dragStartFrame: NSRect?
    private var dragging = false
    private var cancellables: Set<AnyCancellable> = []

    init(store: PetDashboardStore, preferences: PetPreferences) {
        self.store = store
        self.preferences = preferences
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: PetIslandPlacement.baseFloating),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()
        configurePanel()
        observe()
        update()
    }

    private func configurePanel() {
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow
        panel.setAccessibilityTitle("Codex Pet Island")
    }

    private func observe() {
        preferences.$isEnabled
            .removeDuplicates()
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
        preferences.$selectedPetID
            .removeDuplicates()
            .sink { [weak self] _ in self?.rebuildContent() }
            .store(in: &cancellables)
        preferences.$language
            .removeDuplicates()
            .sink { [weak self] _ in self?.rebuildContent() }
            .store(in: &cancellables)
        preferences.$scalePercent
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.scaleDidChange() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenEnvironmentDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenEnvironmentDidChange() {
        expanded = false
        update()
    }

    private func scaleDidChange() {
        let anchor = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
        let size = currentSize
        origin = NSPoint(x: anchor.x - size.width, y: anchor.y - size.height)
        update(animate: false)
    }

    private func toggleExpanded() {
        let anchor = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
        if dockEdge != nil {
            dockEdge = nil
            expanded = true
        } else {
            expanded.toggle()
        }
        let size = currentSize
        origin = NSPoint(x: anchor.x - size.width, y: anchor.y - size.height)
        update()
    }

    private func update(animate: Bool = true) {
        guard preferences.isEnabled, let screen = preferredScreen() else {
            panel.orderOut(nil)
            return
        }
        let targetFrame: NSRect?
        if !dragging {
            let frame = presentationFrame(on: screen)
            targetFrame = frame
            panel.setFrame(
                frame,
                display: true,
                animate: animate && panel.isVisible
            )
        } else {
            targetFrame = nil
        }
        rebuildContent()
        if let targetFrame {
            panel.setFrame(targetFrame, display: true, animate: false)
        }
        panel.orderFrontRegardless()
    }

    private func presentationFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let size = currentSize
        if let dockEdge {
            let y = min(
                visible.maxY - size.height,
                max(visible.minY, origin?.y ?? visible.maxY - size.height - 10)
            )
            let x = dockEdge == .left
                ? visible.minX
                : visible.maxX - size.width
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        }
        let proposed = NSRect(
            origin: origin ?? NSPoint(
                x: visible.maxX - size.width - 14,
                y: visible.maxY - size.height - 10
            ),
            size: size
        )
        return clamp(proposed, to: visible)
    }

    private func clamp(_ frame: NSRect, to visible: NSRect) -> NSRect {
        var result = frame
        result.origin.x = min(
            visible.maxX - frame.width,
            max(visible.minX, frame.minX)
        )
        result.origin.y = min(
            visible.maxY - frame.height,
            max(visible.minY, frame.minY)
        )
        return result
    }

    private func beginDrag() {
        guard !expanded else { return }
        dragStartFrame = panel.frame
        dragging = true
        dockEdge = nil
    }

    private func updateDrag(_ translation: CGSize) {
        guard dragging, let dragStartFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: dragStartFrame.minX + translation.width,
            y: dragStartFrame.minY - translation.height
        ))
    }

    private func endDrag(_ translation: CGSize) {
        guard dragging else { return }
        updateDrag(translation)
        dragging = false
        dragStartFrame = nil

        let screen = screenForPanel()
        screenNumber = number(for: screen)
        let visible = screen.visibleFrame
        let frame = panel.frame
        if frame.minX <= visible.minX + 44 {
            dockEdge = .left
        } else if frame.maxX >= visible.maxX - 44 {
            dockEdge = .right
        } else {
            dockEdge = nil
        }
        origin = clamp(frame, to: visible).origin
        update(animate: false)
    }

    private func screenForPanel() -> NSScreen {
        NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        })
            ?? panel.screen
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func preferredScreen() -> NSScreen? {
        if let screenNumber,
           let screen = NSScreen.screens.first(where: {
               number(for: $0) == screenNumber
           }) {
            return screen
        }
        return panel.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func number(for screen: NSScreen) -> NSNumber? {
        screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber
    }

    private var scale: CGFloat {
        CGFloat(preferences.scalePercent / 100)
    }

    private var currentSize: NSSize {
        PetIslandPlacement.size(
            expanded: expanded,
            docked: dockEdge != nil,
            scale: scale
        )
    }

    private func rebuildContent() {
        let view = PetIslandView(
            store: store,
            preferences: preferences,
            isExpanded: expanded,
            isDocked: dockEdge != nil,
            dockEdge: dockEdge,
            initialDirection: direction,
            toggleExpanded: { [weak self] in self?.toggleExpanded() },
            beginDrag: { [weak self] in self?.beginDrag() },
            changeDirection: { [weak self] in self?.direction = $0 },
            updateDrag: { [weak self] in self?.updateDrag($0) },
            endDrag: { [weak self] in self?.endDrag($0) }
        )
        panel.contentViewController = NSHostingController(rootView: view)
    }
}
