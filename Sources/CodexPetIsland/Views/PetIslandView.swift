import SwiftUI

struct PetIslandView: View {
    @ObservedObject var store: PetDashboardStore
    @ObservedObject var preferences: PetPreferences
    let isExpanded: Bool
    let isDocked: Bool
    let dockEdge: PetDockEdge?
    let initialDirection: PetDockEdge
    let toggleExpanded: () -> Void
    let beginDrag: () -> Void
    let changeDirection: (PetDockEdge) -> Void
    let updateDrag: (CGSize) -> Void
    let endDrag: (CGSize) -> Void

    @State private var direction: PetDockEdge = .right
    @State private var dragging = false

    private var baseScale: CGFloat {
        CGFloat(preferences.scalePercent / 100)
    }

    private var runningTasks: [PetTask] {
        store.snapshot.tasks.filter(\.isRunning)
    }

    private var scale: CGFloat {
        PetIslandPlacement.visualScale(
            baseScale: baseScale,
            subagentScaleMultiplier: hasRunningSubagents
                ? preferences.selectedPet?.subagentScaleMultiplier
                : nil,
            docked: isDocked
        )
    }

    private var hasRunningSubagents: Bool {
        store.snapshot.hasRunningSubagents
    }

    private var size: CGSize {
        PetIslandPlacement.size(
            expanded: isExpanded,
            docked: isDocked,
            scale: scale
        )
    }

    var body: some View {
        ZStack {
            if isDocked {
                dockedPet
                    .overlay { dragCapture(docked: true) }
            } else if isExpanded {
                expandedPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                Button(action: toggleExpanded) {
                    floatingPet
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 10)
            } else {
                Button(action: toggleExpanded) {
                    ZStack(alignment: .bottomTrailing) {
                        if !dragging {
                            collapsedSummary
                                .frame(
                                    maxWidth: .infinity,
                                    maxHeight: .infinity,
                                    alignment: .topLeading
                                )
                        }
                        floatingPet
                    }
                    .frame(
                        width: size.width,
                        height: size.height,
                        alignment: .bottomTrailing
                    )
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottomTrailing) {
                    dragCapture(docked: false)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .onAppear { direction = initialDirection }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text("Codex Pet Island", "Codex 宠物岛"))
    }

    private var collapsedSummary: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(primarySourceLabel) \(primaryTaskTitle)")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(countdownText) \(percentText)")
                    Label(
                        "\(runningTasks.count)",
                        systemImage: runningTasks.isEmpty
                            ? "pause.fill"
                            : "bolt.fill"
                    )
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }
            Spacer()
            splitQuotaRing
        }
        .padding(.horizontal, 13)
        .frame(width: 306, height: 66)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.42), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 13, y: 5)
    }

    private var expandedPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(runningTasks.isEmpty
                        ? Color.gray.opacity(0.16)
                        : Color.green.opacity(0.16))
                    .overlay {
                        Image(systemName: runningTasks.isEmpty
                            ? "checkmark"
                            : "bolt.fill")
                            .foregroundStyle(runningTasks.isEmpty
                                ? Color.secondary
                                : Color.green)
                    }
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                Text(text("Agent tasks", "Agent 任务"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(taskSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: toggleExpanded) {
                    Image(systemName: "chevron.up")
                        .frame(width: 28, height: 28)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
            }
            Divider()
            taskList
            Divider()
            HStack(spacing: 8) {
                metric(label: countdownText, value: percentText)
                metric(
                    label: text("Running", "运行中"),
                    value: "\(runningTasks.count)"
                )
                Spacer(minLength: 2)
                scaleControl
            }
        }
        .padding(14)
        .frame(width: 410, height: 326)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(0.42), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    @ViewBuilder
    private var taskList: some View {
        if store.snapshot.tasks.isEmpty {
            VStack(spacing: 7) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 24))
                Text(text("No recent tasks", "暂无最近任务"))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 172)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.snapshot.tasks) { task in
                        taskRow(task)
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 3)
            }
            .frame(height: 172)
        }
    }

    private func taskRow(_ task: PetTask) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(task.isRunning
                    ? Color.green.opacity(0.16)
                    : Color.orange.opacity(0.16))
                .overlay {
                    Image(systemName: task.isRunning
                        ? "bolt.fill"
                        : "pause.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(task.isRunning
                            ? Color.green
                            : Color.orange)
                }
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("[\(task.source.shortLabel)] \(task.title)")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                Text(
                    "\(task.project) · \(tokenText(task.totalTokens)) · "
                        + (task.isRunning
                            ? text("Running", "运行中")
                            : text("Recent", "最近"))
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.56), in: RoundedRectangle(cornerRadius: 14))
    }

    private var dockedPet: some View {
        VStack(spacing: -6 * scale) {
            ZStack {
                splitQuotaRing
                pet
                    .frame(width: 50 * scale, height: 56 * scale)
            }
            .frame(width: 82 * scale, height: 82 * scale)

        }
        .frame(width: size.width, height: size.height)
        .contentShape(Circle())
    }

    private var floatingPet: some View {
        ZStack(alignment: .bottomTrailing) {
            pet
                .frame(width: 60 * scale, height: 66 * scale)
                .padding(.trailing, 8 * scale)
                .padding(.bottom, 5 * scale)
            Circle()
                .fill(runningTasks.isEmpty ? Color.gray : Color.green)
                .overlay {
                    Text("\(runningTasks.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 20, height: 20)
                .offset(x: -2 * scale, y: -2 * scale)
        }
        .frame(
            width: PetIslandPlacement.petControlSize(scale: scale),
            height: PetIslandPlacement.petControlSize(scale: scale)
        )
        .contentShape(Circle())
    }

    @ViewBuilder
    private var pet: some View {
        if let selected = preferences.selectedPet {
            PetSpriteView(
                pet: selected,
                state: animationState,
                showsSubagentForm: hasRunningSubagents
            )
        } else {
            Image(systemName: "pawprint.fill")
                .resizable()
                .scaledToFit()
                .padding(10)
                .foregroundStyle(.secondary)
        }
    }

    private var animationState: PetAnimationState {
        PetAnimationState.resolve(
            hasRunningTasks: !runningTasks.isEmpty,
            isDragging: dragging,
            direction: direction
        )
    }

    private func dragCapture(docked: Bool) -> some View {
        PetDragCaptureView(
            onClick: toggleExpanded,
            onDragBegan: {
                dragging = true
                beginDrag()
            },
            onDirectionChanged: {
                direction = $0
                changeDirection($0)
            },
            onDragChanged: updateDrag,
            onDragEnded: {
                endDrag($0)
                dragging = false
            }
        )
        .frame(
            width: docked
                ? size.width
                : PetIslandPlacement.petControlSize(scale: scale),
            height: docked
                ? size.height
                : PetIslandPlacement.petControlSize(scale: scale)
        )
    }

    private var scaleControl: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(text("Pet size", "宠物大小"))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("\(Int(preferences.scalePercent))%") {
                    preferences.scalePercent = PetPreferences.defaultScale
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 9, weight: .medium))
            Slider(
                value: $preferences.scalePercent,
                in: PetPreferences.scaleRange,
                step: 5
            )
            .controlSize(.mini)
        }
        .padding(.horizontal, 9)
        .frame(width: 132, height: 42)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .frame(width: 76, height: 42, alignment: .leading)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
    }

    private var splitQuotaRing: some View {
        SplitQuotaRingView(
            codexWeeklyRemaining: store.snapshot.quota?.remainingPercent,
            openCodeGoFiveHourUsed: store.snapshot.openCodeGoQuota?.rolling?.usedPercent,
            openCodeGoWeeklyUsed: store.snapshot.openCodeGoQuota?.weekly?.usedPercent,
            codexWeeklyResetsAt: store.snapshot.quota?.resetsAt,
            openCodeGoFiveHourResetsAt: store.snapshot.openCodeGoQuota?.rolling?.resetsAt,
            openCodeGoWeeklyResetsAt: store.snapshot.openCodeGoQuota?.weekly?.resetsAt,
            scale: isDocked ? scale : 1,
            docked: isDocked
        )
    }

    private var remainingPercent: Int {
        store.snapshot.quota?.remainingPercent ?? 0
    }

    private var percentText: String {
        store.snapshot.quota.map { "\($0.remainingPercent)%" } ?? "--"
    }

    private var primaryQuotaText: String {
        if primaryTask?.source == .openCodeGo,
           let percent = store.snapshot.openCodeGoQuota?.rolling?.usedPercent {
            return "\(percent)%"
        }
        return percentText
    }

    private var countdownText: String {
        let reset: Date?
        if primaryTask?.source == .openCodeGo {
            reset = store.snapshot.openCodeGoQuota?.rolling?.resetsAt
        } else {
            reset = store.snapshot.quota?.resetsAt
        }
        guard let reset else { return "--" }
        let days = max(0, Int(ceil(reset.timeIntervalSinceNow / 86_400)))
        return preferences.language == .chinese ? "\(days)天" : "\(days)d"
    }

    private var primaryTaskTitle: String {
        primaryTask?.title
            ?? text("Codex is resting", "Codex 正在休息")
    }

    private var primaryTask: PetTask? {
        runningTasks.first
            ?? store.snapshot.tasks.sorted { $0.updatedAt > $1.updatedAt }.first
    }

    private var primarySourceLabel: String {
        primaryTask?.source.shortLabel ?? "C"
    }

    private var taskSummary: String {
        text(
            "\(runningTasks.count) running · \(store.snapshot.tasks.count) recent",
            "\(runningTasks.count)个运行中 · 共\(store.snapshot.tasks.count)个最近任务"
        )
    }

    private func tokenText(_ value: Int64) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM Token", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK Token", Double(value) / 1_000)
        }
        return "\(value) Token"
    }

    private func text(_ english: String, _ chinese: String) -> String {
        preferences.language.text(english, chinese)
    }
}
