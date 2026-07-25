import AppKit
import SwiftUI

struct PetDragCaptureView: NSViewRepresentable {
    let onClick: () -> Void
    let onDragBegan: () -> Void
    let onDirectionChanged: (PetDockEdge) -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void

    func makeNSView(context: Context) -> PetDragNSView {
        let view = PetDragNSView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: PetDragNSView, context: Context) {
        update(nsView)
    }

    private func update(_ view: PetDragNSView) {
        view.onClick = onClick
        view.onDragBegan = onDragBegan
        view.onDirectionChanged = onDirectionChanged
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
    }
}

final class PetDragNSView: NSView {
    var onClick: () -> Void = {}
    var onDragBegan: () -> Void = {}
    var onDirectionChanged: (PetDockEdge) -> Void = { _ in }
    var onDragChanged: (CGSize) -> Void = { _ in }
    var onDragEnded: (CGSize) -> Void = { _ in }

    private var start: NSPoint?
    private var isDragging = false

    override func mouseDown(with event: NSEvent) {
        start = NSEvent.mouseLocation
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let delta = translation(from: start)
        if !isDragging, hypot(delta.width, delta.height) >= 3 {
            isDragging = true
            onDragBegan()
        }
        guard isDragging else { return }
        if abs(delta.width) > 2 {
            onDirectionChanged(delta.width < 0 ? .left : .right)
        }
        onDragChanged(delta)
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        let delta = translation(from: start)
        isDragging ? onDragEnded(delta) : onClick()
        self.start = nil
        isDragging = false
    }

    private func translation(from start: NSPoint) -> CGSize {
        let current = NSEvent.mouseLocation
        return CGSize(
            width: current.x - start.x,
            height: start.y - current.y
        )
    }
}
