import SwiftUI

struct SplitQuotaRingView: View {
    let codexWeeklyRemaining: Int?
    let openCodeGoFiveHourUsed: Int?
    let openCodeGoWeeklyUsed: Int?
    let codexWeeklyResetsAt: Date?
    let openCodeGoFiveHourResetsAt: Date?
    let openCodeGoWeeklyResetsAt: Date?
    let scale: CGFloat
    let docked: Bool

    private var size: CGFloat { max(48, 62 * scale) }
    private var line: CGFloat { max(3, 5 * scale) }
    private var codexColor: Color { .purple }
    private var openCodeColor: Color { .green }

    private var openCodeGoFiveHourRemaining: Int? {
        openCodeGoFiveHourUsed.map { max(0, min(100, 100 - $0)) }
    }

    private var openCodeGoWeeklyRemaining: Int? {
        openCodeGoWeeklyUsed.map { max(0, min(100, 100 - $0)) }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        ZStack {
            ring
            providerLabel(
                shortName: "C",
                values: [
                    ("5h --", true, nil),
                    (textValue(codexWeeklyRemaining, prefix: "7d"), false, codexWeeklyResetsAt)
                ],
                color: codexColor,
                alignment: .trailing,
                now: now
            )
            .offset(x: -size * 1.18)
            providerLabel(
                shortName: "G",
                values: [
                    (textValue(openCodeGoFiveHourRemaining, prefix: "5h"), true, openCodeGoFiveHourResetsAt),
                    (textValue(openCodeGoWeeklyRemaining, prefix: "7d"), false, openCodeGoWeeklyResetsAt)
                ],
                color: openCodeColor,
                alignment: .leading,
                now: now
            )
            .offset(x: size * 1.18)
        }
        .frame(width: size * 2.8, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex and OpenCode Go remaining quota")
    }

    private var ring: some View {
        ZStack {
            halfTrack
            halfTrack.scaleEffect(0.76)

            if let codexWeeklyRemaining {
                arc(
                    from: 0.5,
                    value: codexWeeklyRemaining,
                    color: codexColor,
                    width: line * 0.72,
                    scale: 0.76
                )
            }
            if let openCodeGoFiveHourRemaining {
                arc(from: 0, value: openCodeGoFiveHourRemaining, color: openCodeColor, width: line)
            }
            if let openCodeGoWeeklyRemaining {
                arc(
                    from: 0,
                    value: openCodeGoWeeklyRemaining,
                    color: openCodeColor.opacity(0.58),
                    width: line * 0.72,
                    scale: 0.76
                )
            }
        }
        .frame(width: size, height: size)
    }

    private var halfTrack: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.5)
                .stroke(openCodeColor.opacity(0.16), lineWidth: line)
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: 0.5, to: 1)
                .stroke(codexColor.opacity(0.16), lineWidth: line)
                .rotationEffect(.degrees(-90))
        }
    }

    private func arc(
        from start: CGFloat,
        value: Int,
        color: Color,
        width: CGFloat,
        scale: CGFloat = 1
    ) -> some View {
        Circle()
            .trim(from: start, to: start + CGFloat(value) / 200)
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            .scaleEffect(scale)
            .rotationEffect(.degrees(-90))
    }

    private func providerLabel(
        shortName: String,
        values: [(String, Bool, Date?)],
        color: Color,
        alignment: HorizontalAlignment,
        now: Date
    ) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(shortName)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(displayValue(value.0, resetsAt: value.2, now: now))
                    .font(.system(
                        size: docked ? (value.1 ? 13 : 10) : (value.1 ? 10 : 9),
                        weight: value.1 ? .bold : .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(color.opacity(0.88))
            }
        }
        .fixedSize()
    }

    private func textValue(_ value: Int?, prefix: String) -> String {
        guard let value else { return "\(prefix) --" }
        return "\(prefix) \(value)%"
    }

    private func compactValue(_ value: String, resetsAt: Date?, now: Date) -> String {
        let percentage = value.split(separator: " ", maxSplits: 1).last.map(String.init) ?? value
        guard let resetsAt else { return percentage }
        return "\(percentage) · \(resetCountdown(to: resetsAt, now: now))"
    }

    private func displayValue(_ value: String, resetsAt: Date?, now: Date) -> String {
        return compactValue(value, resetsAt: resetsAt, now: now)
    }

    private func resetCountdown(to date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return "\(hours)h\(minutes)m" }
        return "\(max(1, minutes))m"
    }
}
