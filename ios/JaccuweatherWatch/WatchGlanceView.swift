import SwiftUI
import WatchKit

struct WatchGlanceView: View {
    var model: WatchWeatherModel
    @State private var showPlaces = false
    @State private var closedLaunchList = false

    /// Open from the Places button, or from `-watchPlaces 1` until Close.
    private var showingList: Bool {
        if showPlaces { return true }
        if closedLaunchList { return false }
        return WatchFavoritesSample.presentsList
    }

    var body: some View {
        Group {
            if showingList {
                WatchPlacesSheet(model: model) {
                    closedLaunchList = true
                    showPlaces = false
                }
            } else {
                glance
            }
        }
        .preferredColorScheme(.dark)
        .task { await model.start() }
        .onOpenURL { model.open($0) }
    }

    private var glance: some View {
        ZStack {
            WidgetHorizonBackground()
                .ignoresSafeArea()
            fittedStack(metrics)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// 40mm is 197pt and 44mm is 224pt. 45mm (242pt) and larger keep the roomier stack.
    private var metrics: WatchGlanceMetrics {
        WKInterfaceDevice.current().screenBounds.height >= 240 ? .regular : .compact
    }

    private func fittedStack(_ metrics: WatchGlanceMetrics) -> some View {
        glanceStack(metrics)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.bottom, metrics.bottomPadding)
    }

    private func glanceStack(_ metrics: WatchGlanceMetrics) -> some View {
        VStack(spacing: metrics.spacing) {
            placeTitle(metrics)
            HStack(alignment: .center, spacing: 6) {
                symbol(metrics)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.temperatureText)
                        .font(WidgetHorizon.tempFont(size: metrics.tempSize))
                        .foregroundStyle(WidgetHorizon.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if !model.detailText.isEmpty {
                        Text(model.detailText)
                            .font(.system(size: metrics.detailSize, weight: .semibold))
                            .foregroundStyle(WidgetHorizon.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    if model.hours.isEmpty, !model.conditionText.isEmpty {
                        Text(model.conditionText)
                            .font(.system(size: metrics.detailSize, weight: .medium))
                            .foregroundStyle(WidgetHorizon.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            if let sun = model.sun, sun.line != nil {
                WatchSunRow(sun: sun, size: metrics.sunSize)
            }
            if let alert = model.alert {
                WatchAlertBadge(alert: alert)
            }
            WatchHourlyStrip(hours: model.hours, style: metrics.hourly)
            WatchDailyStrip(days: model.days, style: metrics.daily)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.accessibilityLabel)
    }

    private func placeTitle(_ metrics: WatchGlanceMetrics) -> some View {
        ZStack {
            Text(model.placeName)
                .font(WidgetHorizon.placeFont(size: metrics.placeSize))
                .foregroundStyle(WidgetHorizon.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 22)
                .accessibilityIdentifier("watch-place")
            HStack {
                Spacer(minLength: 0)
                Button {
                    showPlaces = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: metrics.placesIcon, weight: .bold))
                        .foregroundStyle(WidgetHorizon.accent)
                        .frame(width: metrics.placesHit, height: metrics.placesHit)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watch-places")
                .accessibilityLabel("Places")
            }
        }
    }

    private func symbol(_ metrics: WatchGlanceMetrics) -> some View {
        Image(systemName: model.symbolName)
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

/// Today's sunrise and sunset under the temperature. One line, no extra metrics.
struct WatchSunRow: View {
    var sun: WatchSunTimes
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 3) {
            if let rise = sun.sunriseLabel {
                Text("↑")
                    .foregroundStyle(WidgetHorizon.gold)
                Text(rise)
                    .foregroundStyle(WidgetHorizon.text)
            }
            if sun.sunriseLabel != nil, sun.sunsetLabel != nil {
                Text("·")
                    .foregroundStyle(WidgetHorizon.faint)
            }
            if let set = sun.sunsetLabel {
                Text("↓")
                    .foregroundStyle(WidgetHorizon.gold)
                Text(set)
                    .foregroundStyle(WidgetHorizon.text)
            }
        }
        .font(.system(size: size, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("watch-sun")
        .accessibilityLabel(sun.spoken)
    }
}

/// Type and strip sizes for the glance. Shorter watches use the compact set
/// so the header, sun line, hours, and day highs and lows all stay on screen.
struct WatchGlanceMetrics {
    var placeSize: CGFloat
    var tempSize: CGFloat
    var detailSize: CGFloat
    var sunSize: CGFloat
    var symbolIcon: CGFloat
    var symbolBox: CGFloat
    var placesIcon: CGFloat
    var placesHit: CGFloat
    var spacing: CGFloat
    var horizontalPadding: CGFloat
    var bottomPadding: CGFloat
    var hourly: WatchStripStyle
    var daily: WatchStripStyle

    static let regular = WatchGlanceMetrics(
        placeSize: 14,
        tempSize: 28,
        detailSize: 11,
        sunSize: 12,
        symbolIcon: 14,
        symbolBox: 24,
        placesIcon: 11,
        placesHit: 20,
        spacing: 1,
        horizontalPadding: 4,
        bottomPadding: 0,
        hourly: .hourlyRegular,
        daily: .dailyRegular
    )

    static let compact = WatchGlanceMetrics(
        placeSize: 13,
        tempSize: 22,
        detailSize: 10,
        sunSize: 11,
        symbolIcon: 12,
        symbolBox: 20,
        placesIcon: 10,
        placesHit: 18,
        spacing: 0,
        horizontalPadding: 2,
        bottomPadding: 2,
        hourly: .hourlyCompact,
        daily: .dailyCompact
    )
}

/// Glass-strip metrics. Column text is sized to fit inside `bandHeight`.
struct WatchStripStyle {
    var columnWidth: CGFloat
    var columnSpacing: CGFloat
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    var labelSize: CGFloat
    var primarySize: CGFloat
    var secondarySize: CGFloat
    var symbolSize: CGFloat
    var cueHeight: CGFloat
    var bandHeight: CGFloat

    static let hourlyRegular = WatchStripStyle(
        columnWidth: 40, columnSpacing: 2, horizontalPadding: 6, verticalPadding: 4,
        labelSize: 11, primarySize: 14, secondarySize: 9, symbolSize: 9, cueHeight: 14, bandHeight: 56
    )
    static let hourlyCompact = WatchStripStyle(
        columnWidth: 36, columnSpacing: 2, horizontalPadding: 4, verticalPadding: 2,
        labelSize: 10, primarySize: 13, secondarySize: 9, symbolSize: 8, cueHeight: 12, bandHeight: 46
    )
    static let dailyRegular = WatchStripStyle(
        columnWidth: 42, columnSpacing: 2, horizontalPadding: 6, verticalPadding: 4,
        labelSize: 11, primarySize: 13, secondarySize: 11, symbolSize: 12, cueHeight: 14, bandHeight: 60
    )
    static let dailyCompact = WatchStripStyle(
        columnWidth: 36, columnSpacing: 2, horizontalPadding: 4, verticalPadding: 2,
        labelSize: 10, primarySize: 12, secondarySize: 10, symbolSize: 11, cueHeight: 12, bandHeight: 58
    )
}

/// Current place plus the phone's favorites. Picking a row switches the glance.
struct WatchPlacesSheet: View {
    var model: WatchWeatherModel
    var onClose: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(model.places) { place in
                    Button {
                        model.select(place)
                        onClose()
                    } label: {
                        HStack(spacing: 6) {
                            Text(place.name)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer(minLength: 4)
                            if model.isSelected(place) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(WidgetHorizon.accent)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityIdentifier(model.isSelected(place) ? "watch-place-selected" : "watch-place-option")
                    .accessibilityLabel(place.name)
                }
            } header: {
                Text("Places")
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
                    .accessibilityIdentifier("watch-places-close")
            }
        }
        .accessibilityIdentifier("watch-places-list")
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
