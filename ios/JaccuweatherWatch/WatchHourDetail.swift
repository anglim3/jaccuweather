import SwiftUI
import WatchKit

/// Short sheet for one place-local hour. Close returns to the glance.
struct WatchHourDetailView: View {
    var hour: WatchHourSlot
    @Environment(\.dismiss) private var dismiss

    private var copy: WatchHourDetailCopy {
        WatchHourlyPlan.detail(for: hour)
    }

    /// 40mm is 197pt. 45mm (242pt) and larger keep the roomier type.
    private var metrics: WatchHourDetailMetrics {
        WKInterfaceDevice.current().screenBounds.height >= 240 ? .regular : .compact
    }

    var body: some View {
        NavigationStack {
            detail(metrics)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, metrics.bottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background {
                    WidgetHorizonBackground()
                        .ignoresSafeArea()
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .accessibilityIdentifier("watch-hour-close")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("watch-hour-detail")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.spoken)
    }

    private func detail(_ metrics: WatchHourDetailMetrics) -> some View {
        VStack(spacing: metrics.spacing) {
            Text(copy.title)
                .font(WidgetHorizon.placeFont(size: metrics.titleSize))
                .foregroundStyle(WidgetHorizon.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("watch-hour-title")

            HStack(spacing: 8) {
                symbol(metrics)
                Text(copy.condition)
                    .font(.system(size: metrics.conditionSize, weight: .semibold))
                    .foregroundStyle(WidgetHorizon.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("watch-hour-condition")
            }

            VStack(spacing: metrics.cardSpacing) {
                Text(copy.temperature)
                    .font(WidgetHorizon.tempFont(size: metrics.tempSize))
                    .foregroundStyle(WidgetHorizon.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("watch-hour-temp")
                if copy.probability != nil || copy.rain != nil || copy.snow != nil {
                    precipRow(metrics)
                }
                if hasExtras {
                    extras(metrics)
                }
            }
            .padding(.horizontal, metrics.cardPadding)
            .padding(.vertical, metrics.cardPadding)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WidgetHorizon.glass)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(WidgetHorizon.glassBorder, lineWidth: 1)
            }
        }
    }

    private var hasExtras: Bool {
        copy.feels != nil || copy.wind != nil || copy.humidity != nil || copy.uv != nil
    }

    private func symbol(_ metrics: WatchHourDetailMetrics) -> some View {
        Image(systemName: hour.symbolName ?? "cloud.fill")
            .font(.system(size: metrics.symbolIcon, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(WidgetHorizon.accent)
            .frame(width: metrics.symbolBox, height: metrics.symbolBox)
            .background {
                Circle()
                    .fill(WidgetHorizon.glassStrong)
                    .overlay {
                        Circle().strokeBorder(WidgetHorizon.glassBorder, lineWidth: 1)
                    }
            }
            .accessibilityHidden(true)
    }

    private func precipRow(_ metrics: WatchHourDetailMetrics) -> some View {
        HStack(spacing: 4) {
            if let probability = copy.probability {
                Text(probability)
                    .font(.system(size: metrics.conditionSize, weight: .semibold))
                    .foregroundStyle(WidgetHorizon.text)
            }
            if let snow = copy.snow {
                cue("snowflake", snow, tint: WidgetHorizon.text, size: metrics.captionSize)
            }
            if let rain = copy.rain {
                cue("drop.fill", rain, tint: WidgetHorizon.accent, size: metrics.captionSize)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityIdentifier("watch-hour-precip")
    }

    private func cue(_ symbol: String, _ amount: String, tint: Color, size: CGFloat) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
            Text(amount)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(WidgetHorizon.text)
        }
        .accessibilityHidden(true)
    }

    /// Feels-like, wind, humidity, and UV, two to a line, only when the hour has them.
    private func extras(_ metrics: WatchHourDetailMetrics) -> some View {
        let rows = extraRows
        return VStack(spacing: 1) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                        Text(item.text)
                            .font(.system(size: metrics.captionSize, weight: .semibold))
                            .foregroundStyle(item.gold ? WidgetHorizon.gold : WidgetHorizon.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier(item.identifier)
                    }
                }
            }
        }
    }

    private var extraRows: [[WatchHourExtra]] {
        var items: [WatchHourExtra] = []
        if let feels = copy.feels {
            items.append(WatchHourExtra(text: feels, identifier: "watch-hour-feels", gold: false))
        }
        if let wind = copy.wind {
            items.append(WatchHourExtra(text: wind, identifier: "watch-hour-wind", gold: false))
        }
        if let humidity = copy.humidity {
            items.append(WatchHourExtra(text: humidity, identifier: "watch-hour-humidity", gold: false))
        }
        if let uv = copy.uv {
            items.append(WatchHourExtra(text: uv, identifier: "watch-hour-uv", gold: true))
        }
        var rows: [[WatchHourExtra]] = []
        var index = 0
        while index < items.count {
            let end = min(index + 2, items.count)
            rows.append(Array(items[index..<end]))
            index = end
        }
        return rows
    }
}

private struct WatchHourExtra {
    var text: String
    var identifier: String
    var gold: Bool
}

/// Type for the hour sheet. Compact watches keep the hour, condition, and card on screen.
struct WatchHourDetailMetrics {
    var titleSize: CGFloat
    var conditionSize: CGFloat
    var tempSize: CGFloat
    var captionSize: CGFloat
    var symbolIcon: CGFloat
    var symbolBox: CGFloat
    var spacing: CGFloat
    var cardSpacing: CGFloat
    var cardPadding: CGFloat
    var horizontalPadding: CGFloat
    var topPadding: CGFloat
    var bottomPadding: CGFloat

    static let regular = WatchHourDetailMetrics(
        titleSize: 16,
        conditionSize: 15,
        tempSize: 28,
        captionSize: 13,
        symbolIcon: 16,
        symbolBox: 32,
        spacing: 6,
        cardSpacing: 4,
        cardPadding: 8,
        horizontalPadding: 4,
        topPadding: 2,
        bottomPadding: 4
    )

    static let compact = WatchHourDetailMetrics(
        titleSize: 14,
        conditionSize: 13,
        tempSize: 24,
        captionSize: 11,
        symbolIcon: 14,
        symbolBox: 26,
        spacing: 3,
        cardSpacing: 2,
        cardPadding: 6,
        horizontalPadding: 2,
        topPadding: 6,
        bottomPadding: 2
    )
}
