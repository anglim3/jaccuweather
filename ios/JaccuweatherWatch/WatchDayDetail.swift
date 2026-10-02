import SwiftUI
import WatchKit

/// Short sheet for one place-local day. Close returns to the glance.
struct WatchDayDetailView: View {
    var day: WatchDaySlot
    @Environment(\.dismiss) private var dismiss

    private var copy: WatchDayDetailCopy {
        WatchDailyPlan.detail(for: day)
    }

    /// 40mm is 197pt. 45mm (242pt) and larger keep the roomier type.
    private var metrics: WatchDayDetailMetrics {
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
                            .accessibilityIdentifier("watch-day-close")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("watch-day-detail")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.spoken)
    }

    private func detail(_ metrics: WatchDayDetailMetrics) -> some View {
        VStack(spacing: metrics.spacing) {
            Text(copy.title)
                .font(WidgetHorizon.placeFont(size: metrics.titleSize))
                .foregroundStyle(WidgetHorizon.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("watch-day-title")

            HStack(spacing: 8) {
                symbol(metrics)
                Text(copy.condition)
                    .font(.system(size: metrics.conditionSize, weight: .semibold))
                    .foregroundStyle(WidgetHorizon.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("watch-day-condition")
            }

            VStack(spacing: metrics.cardSpacing) {
                HStack(spacing: 4) {
                    reading("High", copy.high, size: metrics.tempSize, identifier: "watch-day-high")
                    reading("Low", copy.low, size: metrics.tempSize, identifier: "watch-day-low")
                }
                if copy.probability != nil || copy.rain != nil || copy.snow != nil {
                    precipRow(metrics)
                }
                if let uv = copy.uv {
                    Text(uv)
                        .font(.system(size: metrics.captionSize, weight: .semibold))
                        .foregroundStyle(WidgetHorizon.gold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("watch-day-uv")
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

    private func symbol(_ metrics: WatchDayDetailMetrics) -> some View {
        Image(systemName: day.symbolName)
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

    private func reading(_ caption: String, _ value: String, size: CGFloat, identifier: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(WidgetHorizon.tempFont(size: size))
                .foregroundStyle(WidgetHorizon.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: metricsCaption, weight: .medium))
                .foregroundStyle(WidgetHorizon.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(identifier)
    }

    private var metricsCaption: CGFloat {
        metrics.captionSize
    }

    private func precipRow(_ metrics: WatchDayDetailMetrics) -> some View {
        HStack(spacing: 4) {
            if let probability = copy.probability {
                Text(probability)
                    .font(.system(size: metrics.conditionSize, weight: .semibold))
                    .foregroundStyle(WidgetHorizon.text)
            }
            if let snow = copy.snow {
                cue("snowflake", snow, tint: WidgetHorizon.text)
            }
            if let rain = copy.rain {
                cue("drop.fill", rain, tint: WidgetHorizon.accent)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityIdentifier("watch-day-precip")
    }

    private func cue(_ symbol: String, _ amount: String, tint: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: metrics.captionSize, weight: .semibold))
                .foregroundStyle(tint)
            Text(amount)
                .font(.system(size: metrics.captionSize, weight: .semibold))
                .foregroundStyle(WidgetHorizon.text)
        }
        .accessibilityHidden(true)
    }
}

/// Type for the day sheet. Compact watches keep the title, condition, and card on screen.
struct WatchDayDetailMetrics {
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

    static let regular = WatchDayDetailMetrics(
        titleSize: 16,
        conditionSize: 15,
        tempSize: 26,
        captionSize: 13,
        symbolIcon: 16,
        symbolBox: 32,
        spacing: 6,
        cardSpacing: 6,
        cardPadding: 8,
        horizontalPadding: 4,
        topPadding: 2,
        bottomPadding: 4
    )

    static let compact = WatchDayDetailMetrics(
        titleSize: 14,
        conditionSize: 13,
        tempSize: 22,
        captionSize: 12,
        symbolIcon: 14,
        symbolBox: 26,
        spacing: 4,
        cardSpacing: 3,
        cardPadding: 6,
        horizontalPadding: 2,
        topPadding: 8,
        bottomPadding: 2
    )
}
