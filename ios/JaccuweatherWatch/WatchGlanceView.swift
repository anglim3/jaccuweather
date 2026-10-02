import SwiftUI

struct WatchGlanceView: View {
    var model: WatchWeatherModel

    var body: some View {
        ZStack {
            WidgetHorizonBackground()
                .ignoresSafeArea()
            VStack(spacing: 1) {
                Text(model.placeName)
                    .font(WidgetHorizon.placeFont(size: 14))
                    .foregroundStyle(WidgetHorizon.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("watch-place")
                HStack(alignment: .center, spacing: 6) {
                    symbol
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.temperatureText)
                            .font(WidgetHorizon.tempFont(size: 28))
                            .foregroundStyle(WidgetHorizon.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        if !model.detailText.isEmpty {
                            Text(model.detailText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(WidgetHorizon.accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        if model.hours.isEmpty, !model.conditionText.isEmpty {
                            Text(model.conditionText)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(WidgetHorizon.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
                if let alert = model.alert {
                    WatchAlertBadge(alert: alert)
                        .padding(.top, 1)
                }
                WatchHourlyStrip(hours: model.hours)
                    .padding(.top, 2)
                WatchDailyStrip(days: model.days)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(model.accessibilityLabel)
        }
        .preferredColorScheme(.dark)
        .task { await model.start() }
        .onOpenURL { model.open($0) }
    }

    private var symbol: some View {
        Image(systemName: model.symbolName)
            .font(.system(size: 14, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(WidgetHorizon.accent)
            .frame(width: 24, height: 24)
            .background {
                Circle()
                    .fill(WidgetHorizon.glassStrong)
                    .overlay {
                        Circle().strokeBorder(WidgetHorizon.glassBorder, lineWidth: 1)
                    }
                    .overlay {
                        Circle().fill(
                            RadialGradient(
                                colors: [WidgetHorizon.accent.opacity(0.35), .clear],
                                center: .center,
                                startRadius: 2,
                                endRadius: 28
                            )
                        )
                    }
            }
            .accessibilityHidden(true)
    }
}

/// Compact NWS line. Shown only when the phone payload included a summary.
struct WatchAlertBadge: View {
    var alert: WatchAlertSummary

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .bold))
            Text(line)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            Capsule(style: .continuous)
                .fill(WidgetHorizon.glassStrong)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(tint.opacity(0.55), lineWidth: 1)
                }
        }
        .accessibilityIdentifier("watch-alert-badge")
        .accessibilityLabel(spoken)
    }

    private var line: String {
        if alert.count > 1 {
            return "\(alert.count) · \(alert.title)"
        }
        return alert.title
    }

    private var spoken: String {
        if alert.count > 1 {
            return "\(alert.count) alerts, \(alert.severity), \(alert.title)"
        }
        return "\(alert.severity), \(alert.title)"
    }

    private var tint: Color {
        switch alert.severity.lowercased() {
        case "extreme", "severe":
            return Color(red: 1, green: 0.38, blue: 0.34)
        case "moderate":
            return Color(red: 1, green: 0.62, blue: 0.22)
        case "minor":
            return WidgetHorizon.gold
        default:
            return WidgetHorizon.muted
        }
    }
}
