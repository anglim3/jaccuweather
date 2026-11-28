import SwiftUI
import WatchKit

/// Short sheet for one place-local hour. Close returns to the glance.
struct WatchHourDetailView: View {
    var hour: WatchHourSlot
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var environmentTypeSize
    private var dynamicTypeSize: DynamicTypeSize {
        WatchTextSizeLaunch.forced ?? environmentTypeSize
    }

    private var copy: WatchHourDetailCopy {
        WatchHourlyPlan.detail(for: hour)
    }

    /// 40mm is 197pt. 45mm (242pt) and larger keep the roomier type.
    private var metrics: WatchHourDetailMetrics {
        let base = WKInterfaceDevice.current().screenBounds.height >= 240 ? WatchHourDetailMetrics.regular : .compact
        return base.scaled(by: WatchTextScale.factor(dynamicTypeSize))
    }

    private var roomyText: Bool { WatchTextScale.needsRoom(dynamicTypeSize) }

    var body: some View {
        NavigationStack {
            Group {
                if roomyText {
                    ScrollView {
                        detail(metrics)
                            .padding(.horizontal, metrics.horizontalPadding)
                            .padding(.top, metrics.topPadding)
                            .padding(.bottom, metrics.bottomPadding)
                    }
                } else {
                    detail(metrics)
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.top, metrics.topPadding)
                        .padding(.bottom, metrics.bottomPadding)
                }
            }
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
    }

    private func detail(_ metrics: WatchHourDetailMetrics) -> some View {
        VStack(spacing: metrics.spacing) {
            Text(copy.title)
                .font(WidgetHorizon.placeFont(size: metrics.titleSize))
                .foregroundStyle(WidgetHorizon.text)
                .lineLimit(roomyText ? 2 : 1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("watch-hour-title")

            HStack(spacing: 8) {
                symbol(metrics)
                Text(copy.condition)
                    .font(.system(size: metrics.conditionSize, weight: .semibold))
                    .foregroundStyle(WidgetHorizon.text)
                    .lineLimit(roomyText ? 3 : 2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("watch-hour-condition")
            }

            VStack(spacing: metrics.cardSpacing) {
                Text(copy.temperature)
                    .font(WidgetHorizon.tempFont(size: metrics.tempSize))
                    .foregroundStyle(WidgetHorizon.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("watch-hour-temp")
                    .accessibilityLabel(WatchSpoken.degrees(fromDisplay: copy.temperature))
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
        precipLayout(metrics)
            .minimumScaleFactor(0.6)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("watch-hour-precip")
            .accessibilityLabel(WatchSpoken.hourPrecip(hour) ?? "")
    }

    @ViewBuilder
    private func precipLayout(_ metrics: WatchHourDetailMetrics) -> some View {
        if roomyText {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    precipPieces(metrics)
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 2) {
                    precipPieces(metrics)
                }
            }
        } else {
            HStack(spacing: 4) {
                precipPieces(metrics)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func precipPieces(_ metrics: WatchHourDetailMetrics) -> some View {
        if let probability = copy.probability {
            Text(probability)
                .font(.system(size: metrics.conditionSize, weight: .semibold))
                .foregroundStyle(WidgetHorizon.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        if let snow = copy.snow {
            cue("snowflake", snow, tint: WidgetHorizon.text, size: metrics.captionSize)
        }
        if let rain = copy.rain {
            cue("drop.fill", rain, tint: WidgetHorizon.accent, size: metrics.captionSize)
        }
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
                            .lineLimit(roomyText ? 2 : 1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier(item.identifier)
                            .accessibilityLabel(spokenExtra(item))
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
        let width = roomyText ? 1 : 2
        var index = 0
        while index < items.count {
            let end = min(index + width, items.count)
            rows.append(Array(items[index..<end]))
            index = end
        }
        return rows
    }

    private func spokenExtra(_ item: WatchHourExtra) -> String {
        switch item.identifier {
        case "watch-hour-feels":
            return WatchSpoken.feelsLike(hour.feelsLikeF) ?? item.text
        case "watch-hour-wind":
            return WatchSpoken.windMilesPerHour(hour.windMph) ?? item.text
        case "watch-hour-humidity":
            return WatchSpoken.humidityPercent(hour.humidity) ?? item.text
        case "watch-hour-uv":
            return WatchSpoken.ultraviolet(index: hour.uvIndex) ?? item.text
        default:
            return WatchSpoken.degrees(fromDisplay: item.text)
        }
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

    func scaled(by factor: CGFloat) -> WatchHourDetailMetrics {
        guard factor > 1.001 else { return self }
        return WatchHourDetailMetrics(
            titleSize: titleSize * factor,
            conditionSize: conditionSize * factor,
            tempSize: tempSize * factor,
            captionSize: captionSize * factor,
            symbolIcon: symbolIcon * min(factor, 1.4),
            symbolBox: symbolBox * min(factor, 1.4),
            spacing: spacing,
            cardSpacing: cardSpacing,
            cardPadding: cardPadding,
            horizontalPadding: horizontalPadding,
            topPadding: topPadding,
            bottomPadding: bottomPadding
        )
    }
}
