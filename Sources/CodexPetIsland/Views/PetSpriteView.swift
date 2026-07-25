import AppKit
import SwiftUI

enum PetAnimationState: Equatable {
    case idle
    case runningLeft
    case runningRight
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
        TimelineView(.periodic(from: .now, by: frameInterval)) { context in
            if let image {
                let tick = Int(
                    context.date.timeIntervalSinceReferenceDate / frameInterval
                )
                spriteSheet(image, frame: tick % frameCount)
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
                    y: -CGFloat(row) * proxy.size.height
                )
        }
        .clipped()
    }

    private var row: Int {
        switch state {
        case .idle: 0
        case .runningRight: 1
        case .runningLeft: 2
        }
    }

    private var frameCount: Int {
        state == .idle ? 7 : 8
    }

    private var frameInterval: TimeInterval {
        state == .idle ? 0.55 : 0.15
    }
}
