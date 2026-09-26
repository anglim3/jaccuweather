import SwiftUI
import WidgetKit

struct ConditionsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetConditionsSnapshot?
    /// Set when a place is chosen but Open-Meteo did not return a reading.
    let unavailablePlaceName: String?
}

struct ConditionsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ConditionsEntry {
        ConditionsEntry(date: Date(), snapshot: .gallery, unavailablePlaceName: nil)
    }

    func snapshot(for configuration: PlaceWidgetIntent, in context: Context) async -> ConditionsEntry {
        let stored = WidgetSnapshotStore.load()
        if let stored {
            return ConditionsEntry(date: Date(), snapshot: stored, unavailablePlaceName: nil)
        }
        if context.isPreview {
            let sample = configuration.place.map(WidgetConditionsSnapshot.preview(for:)) ?? .gallery
            return ConditionsEntry(date: Date(), snapshot: sample, unavailablePlaceName: nil)
        }
        if let place = configuration.place {
            return ConditionsEntry(
                date: Date(),
                snapshot: .shell(
                    locationId: place.id,
                    locationName: place.name,
                    latitude: place.latitude,
                    longitude: place.longitude
                ),
                unavailablePlaceName: nil
            )
        }
        return ConditionsEntry(date: Date(), snapshot: nil, unavailablePlaceName: nil)
    }

    func timeline(for configuration: PlaceWidgetIntent, in context: Context) async -> Timeline<ConditionsEntry> {
        let loaded = await WidgetTimelineLoader.load(place: configuration.place)
        let entry = ConditionsEntry(
            date: Date(),
            snapshot: loaded.snapshot,
            unavailablePlaceName: loaded.unavailablePlaceName
        )
        let interval: TimeInterval = loaded.snapshot == nil ? 5 * 60 : 20 * 60
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(interval)))
    }
}

enum WidgetTimelineLoader {
    struct Loaded {
        var snapshot: WidgetConditionsSnapshot?
        var unavailablePlaceName: String?
    }

    /// Fresh App Group snapshot wins. Otherwise fetch the configured place.
    /// A missing container (Personal Team) skips the snapshot and uses that place.
    static func load(place: WidgetPlace?) async -> Loaded {
        let stored = WidgetSnapshotStore.load()
        if let stored, stored.isFresh {
            return Loaded(snapshot: stored, unavailablePlaceName: nil)
        }
        if let place,
           let fetched = await WidgetCurrentRefresh.fetch(
               name: place.name,
               latitude: place.latitude,
               longitude: place.longitude,
               locationId: place.id
           ) {
            return Loaded(snapshot: fetched, unavailablePlaceName: nil)
        }
        if let stored {
            if let refreshed = await WidgetCurrentRefresh.refresh(stored) {
                WidgetSnapshotStore.save(refreshed, reloadWidgets: false)
                return Loaded(snapshot: refreshed, unavailablePlaceName: nil)
            }
            if stored.age < WidgetConditionsSnapshot.showStaleUntil {
                return Loaded(snapshot: stored, unavailablePlaceName: nil)
            }
        }
        if let place {
            return Loaded(snapshot: nil, unavailablePlaceName: place.name)
        }
        return Loaded(snapshot: nil, unavailablePlaceName: nil)
    }
}

struct ConditionsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetSnapshotStore.kind, intent: PlaceWidgetIntent.self, provider: ConditionsProvider()) { entry in
            ConditionsWidgetView(entry: entry)
        }
        .configurationDisplayName("Current conditions")
        .description("Temperature and sky for a place you choose. A fresh reading from the app is used when sharing is available.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct ConditionsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    var entry: ConditionsEntry

    private var navy: Color { Color(red: 13 / 255, green: 33 / 255, blue: 55 / 255) }
    private var accent: Color { Color(red: 125 / 255, green: 211 / 255, blue: 252 / 255) }

    private var accessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        default:
            return false
        }
    }

    private var titleColor: Color {
        accessory || renderingMode == .accented ? .primary : .white
    }

    private var mutedColor: Color {
        accessory || renderingMode == .accented ? .secondary : Color.white.opacity(0.65)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .containerBackground(for: .widget) { background }
    }

    private var alignment: Alignment {
        switch family {
        case .accessoryCircular, .accessoryInline:
            return .center
        default:
            return .leading
        }
    }

    @ViewBuilder
    private var background: some View {
        switch family {
        case .accessoryCircular:
            AccessoryWidgetBackground()
        case .accessoryRectangular, .accessoryInline:
            Color.clear
        default:
            navy
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            populated(snapshot)
        } else if let name = entry.unavailablePlaceName {
            unavailable(name)
        } else {
            configurePrompt
        }
    }

    @ViewBuilder
    private func populated(_ snapshot: WidgetConditionsSnapshot) -> some View {
        switch family {
        case .systemMedium:
            medium(snapshot)
        case .accessoryCircular:
            circular(snapshot)
        case .accessoryRectangular:
            rectangular(snapshot)
        case .accessoryInline:
            inline(snapshot)
        default:
            small(snapshot)
        }
    }

    private func small(_ snapshot: WidgetConditionsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.locationName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(mutedColor)
                .lineLimit(1)
            HStack(alignment: .center, spacing: 8) {
                Text(degrees(snapshot.temperatureF))
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .foregroundStyle(titleColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .widgetAccentable()
                Spacer(minLength: 0)
                symbol(snapshot.symbolName, size: 28)
            }
            Text(snapshot.conditionText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let chance = snapshot.precipChance {
                Text("\(chance)% precip")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(mutedColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(snapshot))
    }

    private func medium(_ snapshot: WidgetConditionsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.locationName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(mutedColor)
                        .lineLimit(1)
                    Text(degrees(snapshot.temperatureF))
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .foregroundStyle(titleColor)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .widgetAccentable()
                    Text(snapshot.conditionText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                symbol(snapshot.symbolName, size: 40)
            }
            HStack(spacing: 12) {
                Text("Feels \(degrees(snapshot.feelsLikeF))")
                Text("H \(degrees(snapshot.highF))")
                Text("L \(degrees(snapshot.lowF))")
                if let chance = snapshot.precipChance {
                    Text("\(chance)%")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(mutedColor)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            if !snapshot.nextHoursHint.isEmpty {
                Text(snapshot.nextHoursHint)
                    .font(.caption2)
                    .foregroundStyle(mutedColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(snapshot))
    }

    private func circular(_ snapshot: WidgetConditionsSnapshot) -> some View {
        VStack(spacing: 1) {
            symbol(snapshot.symbolName, size: 16)
            Text(degrees(snapshot.temperatureF))
                .font(.caption.weight(.bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .widgetAccentable()
        }
        .accessibilityLabel(spoken(snapshot))
    }

    private func rectangular(_ snapshot: WidgetConditionsSnapshot) -> some View {
        HStack(spacing: 8) {
            symbol(snapshot.symbolName, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(degrees(snapshot.temperatureF))  \(snapshot.locationName)")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                Text(detailLine(snapshot))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(snapshot))
    }

    private func inline(_ snapshot: WidgetConditionsSnapshot) -> some View {
        Text("\(degrees(snapshot.temperatureF)) \(snapshot.conditionText)")
            .widgetAccentable()
            .accessibilityLabel(spoken(snapshot))
    }

    @ViewBuilder
    private var configurePrompt: some View {
        let hint = "Touch and hold, tap Edit Widget, then search for a city or enter coordinates."
        switch family {
        case .accessoryCircular:
            VStack(spacing: 1) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.body)
                Text("Edit")
                    .font(.caption2.weight(.semibold))
            }
            .accessibilityLabel("Choose a place. \(hint)")
        case .accessoryInline:
            Text("Choose a place")
                .accessibilityLabel("Choose a place. \(hint)")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Choose a place")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Edit this widget")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Choose a place. \(hint)")
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title2)
                    .foregroundStyle(accessory || renderingMode == .accented ? Color.primary : accent)
                    .widgetAccentable()
                Text("Choose a place")
                    .font(.headline)
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(mutedColor)
                    .lineLimit(4)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Choose a place. \(hint)")
        }
    }

    @ViewBuilder
    private func unavailable(_ name: String) -> some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 1) {
                Image(systemName: "exclamationmark.icloud")
                    .font(.body)
                Text("—")
                    .font(.caption2.weight(.semibold))
            }
            .accessibilityLabel("Couldn't load weather for \(name)")
        case .accessoryInline:
            Text(name)
                .accessibilityLabel("Couldn't load weather for \(name)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("Couldn't load weather")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Couldn't load weather for \(name)")
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(mutedColor)
                    .lineLimit(1)
                Text("Couldn't load weather")
                    .font(.headline)
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Couldn't load weather for \(name)")
        }
    }

    private func symbol(_ name: String, size: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(accessory || renderingMode == .accented ? Color.primary : accent)
            .widgetAccentable()
            .accessibilityHidden(true)
    }

    private func degrees(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))°"
    }

    private func detailLine(_ snapshot: WidgetConditionsSnapshot) -> String {
        if let chance = snapshot.precipChance {
            return "\(snapshot.conditionText) · \(chance)%"
        }
        return snapshot.conditionText
    }

    private func spoken(_ snapshot: WidgetConditionsSnapshot) -> String {
        var parts = [snapshot.locationName, degrees(snapshot.temperatureF), snapshot.conditionText]
        if let feels = snapshot.feelsLikeF {
            parts.append("feels like \(Int(feels.rounded())) degrees")
        }
        if let chance = snapshot.precipChance {
            parts.append("\(chance) percent chance of precipitation")
        }
        return parts.joined(separator: ", ")
    }
}

private extension WidgetConditionsSnapshot {
    static func preview(for place: WidgetPlace) -> WidgetConditionsSnapshot {
        var sample = gallery
        sample.locationId = place.id
        sample.locationName = place.name
        sample.latitude = place.latitude
        sample.longitude = place.longitude
        return sample
    }

    static let gallery = WidgetConditionsSnapshot(
        locationId: "47.6062,-122.3321",
        locationName: "Seattle",
        latitude: 47.6062,
        longitude: -122.3321,
        temperatureF: 62,
        feelsLikeF: 60,
        weatherCode: 2,
        isDay: true,
        conditionText: "Partly cloudy",
        symbolName: "cloud.sun.fill",
        precipChance: 20,
        highF: 68,
        lowF: 54,
        nextHoursHint: "4p 64° · 5p 63° 40% · 6p 61° · 7p 59°",
        fetchedAt: Date()
    )
}

@main
struct JaccuweatherWidgets: WidgetBundle {
    var body: some Widget {
        ConditionsWidget()
    }
}
