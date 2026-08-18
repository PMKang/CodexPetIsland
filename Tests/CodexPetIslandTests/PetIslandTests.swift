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

    func testLocalReaderDoesNotUseSessionRateLimits() throws {
        let root = try makeCodexDirectory(
            eventLines: [
                """
                {"timestamp":"2026-07-29T10:00:00.000Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":42,"window_minutes":10080,"resets_at":1785752532}}}}
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = LocalCodexReader(codexDirectory: root).read()

        XCTAssertNil(snapshot.quota)
    }

    func testAppServerSelectsMainCodexWeeklyWindow() throws {
        let quota = try CodexAppServerQuotaClient.parseRateLimitsResponse(
            [
                "rateLimitsByLimitId": [
                    "codex_bengalfox": [
                        "limitId": "codex_bengalfox",
                        "primary": [
                            "usedPercent": 0,
                            "windowDurationMins": 10_080,
                            "resetsAt": 1_800_500_000
                        ]
                    ],
                    "codex": [
                        "limitId": "codex",
                        "primary": [
                            "usedPercent": 6,
                            "windowDurationMins": 10_080,
                            "resetsAt": 1_800_500_000
                        ],
                        "secondary": NSNull()
                    ]
                ]
            ]
        )

        XCTAssertEqual(quota.label, "7d")
        XCTAssertEqual(quota.remainingPercent, 94)
    }

    func testAppServerClassifiesWindowsByDurationNotSlot() throws {
        let quota = try CodexAppServerQuotaClient.parseRateLimitsResponse([
            "rateLimits": [
                "limitId": "codex",
                "primary": [
                    "usedPercent": 35,
                    "windowDurationMins": 300,
                    "resetsAt": 1_800_100_000
                ],
                "secondary": [
                    "usedPercent": 12,
                    "windowDurationMins": 10_080,
                    "resetsAt": 1_800_500_000
                ]
            ]
        ])

        XCTAssertEqual(quota.label, "7d")
        XCTAssertEqual(quota.remainingPercent, 88)
        XCTAssertEqual(
            quota.resetsAt,
            Date(timeIntervalSince1970: 1_800_500_000)
        )
    }

    func testParsesOpenCodeGoUsageWindows() throws {
        let snapshot = try OpenCodeGoQuotaClient.parse(
            data: Data(
                """
                {"usage":{"rolling":{"status":"ok","percent":23,"resetsAt":"2026-08-18T06:15:58.044Z"},"weekly":{"status":"ok","percent":20,"resetsAt":"2026-08-24T00:00:00.044Z"},"monthly":{"status":"ok","percent":10,"resetsAt":"2026-09-17T16:34:11.044Z"}}}
                """.utf8
            )
        )

        XCTAssertEqual(snapshot.rolling?.usedPercent, 23)
        XCTAssertEqual(snapshot.weekly?.usedPercent, 20)
        XCTAssertNotNil(snapshot.rolling?.resetsAt)
    }

    func testLiveAppServerReturnsOfficialWeeklyQuota() throws {
        guard ProcessInfo.processInfo.environment[
            "CODEX_PET_ISLAND_LIVE_TEST"
        ] == "1" else {
            throw XCTSkip("Set CODEX_PET_ISLAND_LIVE_TEST=1 to query Codex")
        }

        let quota = try CodexAppServerQuotaClient(timeout: 12).fetchQuota()

        XCTAssertTrue((0 ... 100).contains(quota.remainingPercent))
        XCTAssertFalse(quota.label.isEmpty)
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
