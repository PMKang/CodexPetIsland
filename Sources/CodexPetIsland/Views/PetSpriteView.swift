import AppKit
import SwiftUI

enum PetAnimationState: Equatable {
    case idle
    case runningLeft
    case runningRight
    case taskRunning

    var spriteRow: Int {
        switch self {
        case .idle: 0
        case .runningRight: 1
        case .runningLeft: 2
        case .taskRunning: 7
        }
    }

    var frameCount: Int {
        switch self {
        case .idle, .taskRunning: 6
        case .runningLeft, .runningRight: 8
        }
    }

    var frameInterval: TimeInterval {
        switch self {
        case .idle: 0.28
        case .runningLeft, .runningRight, .taskRunning: 0.12
        }
    }
}

struct PetSpriteView: View {
    let pet: CodexPet
    let state: PetAnimationState
    private let image: NSImage?
    private let columns = 8
    private var rows: Int { pet.spriteVersionNumber == 2 ? 11 : 9 }

    init(pet: CodexPet, state: PetAnimationState) {
        self.pet = pet
        self.state = state
        image = NSImage(contentsOf: pet.spritesheetURL)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: state.frameInterval)) { context in
            if let image {
                let tick = Int(
                    context.date.timeIntervalSinceReferenceDate
                        / state.frameInterval
                )
                spriteSheet(image, frame: tick % state.frameCount)
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
