import AppKit
import SwiftUI

enum PetAnimationState: Equatable {
    case idle
    case runningLeft
    case runningRight
    case taskRunning
    case taskRunningLeft
    case taskRunningRight

    static func resolve(
        hasRunningTasks: Bool,
        isDragging: Bool,
        direction: PetDockEdge
    ) -> Self {
        if hasRunningTasks && isDragging {
            return direction == .left ? .taskRunningLeft : .taskRunningRight
        }
        if hasRunningTasks {
            return .taskRunning
        }
        if isDragging {
            return direction == .left ? .runningLeft : .runningRight
        }
        return .idle
    }

    var spriteRow: Int {
        switch self {
        case .idle: 0
        case .runningRight: 1
        case .runningLeft: 2
        case .taskRunning, .taskRunningLeft, .taskRunningRight: 7
        }
    }

    var frameCount: Int {
        switch self {
        case .idle, .taskRunning, .taskRunningLeft, .taskRunningRight: 6
        case .runningLeft, .runningRight: 8
        }
    }

    var frameInterval: TimeInterval {
        switch self {
        case .idle: 0.28
        case .runningLeft, .runningRight, .taskRunning,
             .taskRunningLeft, .taskRunningRight: 0.12
        }
    }

    var taskRunningDirection: PetDockEdge? {
        switch self {
        case .taskRunningLeft: .left
        case .taskRunningRight: .right
        default: nil
        }
    }
}

struct PetSpriteView: View {
    let pet: CodexPet
    let state: PetAnimationState
    let showsSubagentForm: Bool
    private let image: NSImage?
    private let subagentImage: NSImage?
    private let columns = 8
    private var rows: Int { pet.spriteVersionNumber == 2 ? 11 : 9 }

    init(
        pet: CodexPet,
        state: PetAnimationState,
        showsSubagentForm: Bool = false
    ) {
        self.pet = pet
        self.state = state
        self.showsSubagentForm = showsSubagentForm
        image = NSImage(contentsOf: pet.spritesheetURL)
        subagentImage = pet.subagentFormURL.flatMap(NSImage.init(contentsOf:))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: state.frameInterval)) { context in
            let tick = Int(
                context.date.timeIntervalSinceReferenceDate
                    / state.frameInterval
            )
            if showsSubagentForm, let subagentImage {
                Image(nsImage: subagentImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .offset(
                        x: directionalStride(tick: tick),
                        y: directionalBounce(tick: tick)
                    )
                    .rotationEffect(
                        .degrees(directionalLean),
                        anchor: .bottom
                    )
            } else if let image {
                spriteSheet(image, frame: tick % state.frameCount)
                    .offset(
                        x: directionalStride(tick: tick),
                        y: directionalBounce(tick: tick)
                    )
                    .rotationEffect(
                        .degrees(directionalLean),
                        anchor: .bottom
                    )
            } else {
                Image(systemName: "pawprint.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("\(pet.displayName) Codex pet")
    }

    private func directionalStride(tick: Int) -> CGFloat {
        guard let direction = state.taskRunningDirection else { return 0 }
        let stride: CGFloat = tick.isMultiple(of: 2) ? 1.5 : 3
        return direction == .left ? -stride : stride
    }

    private func directionalBounce(tick: Int) -> CGFloat {
        guard state.taskRunningDirection != nil else { return 0 }
        return tick.isMultiple(of: 2) ? -2 : 1
    }

    private var directionalLean: Double {
        switch state.taskRunningDirection {
        case .left: -5
        case .right: 5
        case nil: 0
        }
    }

    private func spriteSheet(_ image: NSImage, frame: Int) -> some View {
        GeometryReader { proxy in
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .frame(
                    width: proxy.size.width * CGFloat(columns),
                    height: proxy.size.height * CGFloat(rows),
                    alignment: .topLeading
                )
                .offset(
                    x: -CGFloat(frame) * proxy.size.width,
                    y: -CGFloat(state.spriteRow) * proxy.size.height
                )
        }
        .clipped()
    }
}
