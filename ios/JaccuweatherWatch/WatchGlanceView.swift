import SwiftUI

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
            VStack(spacing: 1) {
                placeTitle
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
    }

    private var placeTitle: some View {
        ZStack {
            Text(model.placeName)
                .font(WidgetHorizon.placeFont(size: 14))
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
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WidgetHorizon.accent)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watch-places")
                .accessibilityLabel("Places")
            }
        }
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
