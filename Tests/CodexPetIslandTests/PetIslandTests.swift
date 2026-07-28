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

    func testRunningTaskKeepsProcessingFormWhileDragging() {
        let left = PetAnimationState.resolve(
            hasRunningTasks: true,
            isDragging: true,
            direction: .left
        )
        let right = PetAnimationState.resolve(
            hasRunningTasks: true,
            isDragging: true,
            direction: .right
        )

        XCTAssertEqual(left, .taskRunningLeft)
        XCTAssertEqual(right, .taskRunningRight)
        XCTAssertEqual(left.spriteRow, 7)
        XCTAssertEqual(right.spriteRow, 7)
        XCTAssertEqual(left.taskRunningDirection, .left)
        XCTAssertEqual(right.taskRunningDirection, .right)
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

    func testConfiguredSubagentFormScalesWithoutChangingDockedSize() {
        XCTAssertEqual(
            PetIslandPlacement.visualScale(
                baseScale: 1,
                subagentScaleMultiplier: 1.5,
                docked: false
            ),
            1.5
        )
        XCTAssertEqual(
            PetIslandPlacement.visualScale(
                baseScale: 3,
                subagentScaleMultiplier: 1.5,
                docked: false
            ),
            4.5
        )
        XCTAssertEqual(
            PetIslandPlacement.visualScale(
                baseScale: 3,
                subagentScaleMultiplier: 1.5,
                docked: true
            ),
            3
        )
        XCTAssertEqual(
            PetIslandPlacement.visualScale(
                baseScale: 1,
                subagentScaleMultiplier: nil,
                docked: false
            ),
            1
        )
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

    func testAdditionalModelQuotaDoesNotReplaceMainCodexQuota() throws {
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
            {"timestamp":"2026-07-27T06:15:20.154Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":11,"window_minutes":10080,"resets_at":1785621106},"secondary":null}}}
            """.utf8
        ).write(to: sessions.appendingPathComponent("main-quota.jsonl"))
        try Data(
            """
            {"timestamp":"2026-07-27T10:22:26.394Z","payload":{"rate_limits":{"limit_id":"codex_bengalfox","limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":0,"window_minutes":10080,"resets_at":1785752532},"secondary":null}}}
            """.utf8
        ).write(to: sessions.appendingPathComponent("additional-quota.jsonl"))

        let snapshot = LocalCodexReader(
            codexDirectory: root,
            now: { Date(timeIntervalSince1970: 1_785_136_501) }
        ).read()

        XCTAssertEqual(snapshot.quota?.remainingPercent, 89)
        XCTAssertEqual(
            snapshot.quota?.resetsAt,
            Date(timeIntervalSince1970: 1_785_621_106)
        )
    }

    func testRecentCompletedTaskIsNotReportedAsRunning() throws {
        let root = try makeCodexDirectory(
            eventLines: [
                lifecycleEvent("task_started"),
                lifecycleEvent("task_complete")
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = LocalCodexReader(codexDirectory: root).read()

        XCTAssertEqual(snapshot.tasks.first?.isRunning, false)
    }

    func testLifecycleStartOverridesModificationTimeFallback() throws {
        let root = try makeCodexDirectory(
            eventLines: [lifecycleEvent("task_started")]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try XCTUnwrap(
            FileManager.default.enumerator(
                at: root.appendingPathComponent("sessions"),
                includingPropertiesForKeys: nil
            )?.allObjects.compactMap { $0 as? URL }
                .first(where: { $0.pathExtension == "jsonl" })
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -600)],
            ofItemAtPath: session.path
        )

        let snapshot = LocalCodexReader(codexDirectory: root).read()

        XCTAssertEqual(snapshot.tasks.first?.isRunning, true)
    }

    func testSubagentMetadataUsesIndependentFormTrigger() throws {
        let root = try makeCodexDirectory(
            eventLines: [
                """
                {"type":"session_meta","payload":{"session_id":"parent","id":"child","cwd":"/tmp/project","thread_source":"subagent","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent"}}}}}
                """,
                lifecycleEvent("task_started")
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = LocalCodexReader(codexDirectory: root).read()

        XCTAssertEqual(snapshot.tasks.first?.id, "child")
        XCTAssertEqual(snapshot.tasks.first?.isSubagent, true)
        XCTAssertEqual(snapshot.hasRunningSubagents, true)
    }

    private func makeCodexDirectory(eventLines: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-lifecycle-\(UUID().uuidString)")
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(
            at: sessions,
            withIntermediateDirectories: true
        )
        try Data(eventLines.joined(separator: "\n").utf8).write(
            to: sessions.appendingPathComponent("session.jsonl")
        )
        return root
    }

    private func lifecycleEvent(_ type: String) -> String {
        """
        {"type":"event_msg","payload":{"type":"\(type)"}}
        """
    }
}
