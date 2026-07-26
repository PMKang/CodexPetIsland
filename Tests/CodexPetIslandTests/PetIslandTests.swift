import AppKit
import Foundation
import XCTest
@testable import CodexPetIsland

final class PetIslandTests: XCTestCase {
    func testTaskRunningUsesOfficialProcessingAnimationRow() {
        XCTAssertEqual(PetAnimationState.taskRunning.spriteRow, 7)
        XCTAssertEqual(PetAnimationState.taskRunning.frameCount, 6)
    }

    func testIdleDoesNotReadTheFirstUnusedTransparentCell() {
        XCTAssertEqual(PetAnimationState.idle.spriteRow, 0)
        XCTAssertEqual(PetAnimationState.idle.frameCount, 6)
    }

    func testDraggingAnimationsRemainDirectional() {
        XCTAssertEqual(PetAnimationState.runningRight.spriteRow, 1)
        XCTAssertEqual(PetAnimationState.runningLeft.spriteRow, 2)
        XCTAssertEqual(PetAnimationState.runningRight.frameCount, 8)
        XCTAssertEqual(PetAnimationState.runningLeft.frameCount, 8)
    }

    func testThreeHundredPercentSizesRemainFinite() {
        let floating = PetIslandPlacement.size(
            expanded: false,
            docked: false,
            scale: 3
        )
        let expanded = PetIslandPlacement.size(
            expanded: true,
            docked: false,
            scale: 3
        )
        let docked = PetIslandPlacement.size(
            expanded: false,
            docked: true,
            scale: 3
        )

        XCTAssertEqual(floating, NSSize(width: 324, height: 288))
        XCTAssertEqual(expanded, NSSize(width: 410, height: 536))
        XCTAssertEqual(docked, NSSize(width: 312, height: 336))
    }

    func testReadsSelectedCustomPetID() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-pet-\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(
            """
            model = "gpt-5"
            selected-avatar-id = "custom:sharkler"
            """.utf8
        ).write(to: url)

        XCTAssertEqual(
            CodexPetSelectionReader(configURL: url).selectedPetID(),
            "sharkler"
        )
    }

    func testUsesNewestRateLimitEventAcrossSessionFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-reader-\(UUID().uuidString)")
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(
            at: sessions,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(
            """
            {"timestamp":"2026-07-25T10:00:00.000Z","payload":{"rate_limits":{"primary":{"used_percent":10,"window_minutes":10080,"resets_at":1785275523},"secondary":null}}}
            """.utf8
        ).write(to: sessions.appendingPathComponent("newer-file.jsonl"))
        try Data(
            """
            {"timestamp":"2026-07-26T10:00:00.000Z","payload":{"rate_limits":{"primary":{"used_percent":96,"window_minutes":10080,"resets_at":1785275523},"secondary":null}}}
            """.utf8
        ).write(to: sessions.appendingPathComponent("newer-event.jsonl"))

        let snapshot = LocalCodexReader(
            codexDirectory: root,
            now: { Date(timeIntervalSince1970: 1_785_000_000) }
        ).read()

        XCTAssertEqual(snapshot.quota?.remainingPercent, 4)
        XCTAssertEqual(snapshot.quota?.label, "7d")
    }
}
