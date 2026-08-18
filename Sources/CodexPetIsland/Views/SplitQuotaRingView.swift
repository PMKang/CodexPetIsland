import SwiftUI

struct SplitQuotaRingView: View {
    let codexWeeklyRemaining: Int?
    let openCodeGoFiveHourUsed: Int?
    let openCodeGoWeeklyUsed: Int?
    let scale: CGFloat

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
        HStack(spacing: max(4, 7 * scale)) {
            providerLabel(
                shortName: "C",
                values: [
                    ("5h --", true),
                    (textValue(codexWeeklyRemaining, prefix: "7d"), false)
                ],
                color: codexColor,
                alignment: .trailing
            )
            ring
            providerLabel(
                shortName: "G",
                values: [
                    (textValue(openCodeGoFiveHourRemaining, prefix: "5h"), true),
                    (textValue(openCodeGoWeeklyRemaining, prefix: "7d"), false)
                ],
                color: openCodeColor,
                alignment: .leading
            )
        }
        .frame(minWidth: size * 1.75, minHeight: size)
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
        values: [(String, Bool)],
        color: Color,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: max(0, 1 * scale)) {
            Text(shortName)
                .font(.system(size: max(9, 11 * scale), weight: .bold, design: .rounded))
                .foregroundStyle(color)
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value.0)
                    .font(.system(
                        size: max(7, (value.1 ? 10 : 9) * scale),
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
}
