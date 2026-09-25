import SwiftUI
import WidgetKit

struct ConditionsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetConditionsSnapshot?
}

struct ConditionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> ConditionsEntry {
        ConditionsEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ConditionsEntry) -> Void) {
        let stored = WidgetSnapshotStore.load()
        if context.isPreview, stored == nil {
            completion(ConditionsEntry(date: Date(), snapshot: .gallery))
            return
        }
        completion(ConditionsEntry(date: Date(), snapshot: stored))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ConditionsEntry>) -> Void) {
        Task {
            let snapshot = await WidgetTimelineLoader.load()
            let entry = ConditionsEntry(date: Date(), snapshot: snapshot)
            let next = Date().addingTimeInterval(20 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

enum WidgetTimelineLoader {
    static func load() async -> WidgetConditionsSnapshot? {
        guard let stored = WidgetSnapshotStore.load() else { return nil }
        if stored.isFresh { return stored }
        if let refreshed = await WidgetCurrentRefresh.refresh(stored) {
            WidgetSnapshotStore.save(refreshed, reloadWidgets: false)
            return refreshed
        }
        if stored.age < WidgetConditionsSnapshot.showStaleUntil { return stored }
        return nil
    }
}

struct ConditionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.kind, provider: ConditionsProvider()) { entry in
            ConditionsWidgetView(entry: entry)
        }
        .configurationDisplayName("Current conditions")
        .description("Temperature, sky, and rain chance for the place open in Jaccuweather.")
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
        } else {
            placeholder
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
    private var placeholder: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 1) {
                Image(systemName: "cloud.sun.fill")
                    .font(.body)
                Text("Open")
                    .font(.caption2.weight(.semibold))
            }
            .accessibilityLabel("Open Jaccuweather")
        case .accessoryInline:
            Text("Open Jaccuweather")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "cloud.sun.fill")
                    .font(.title3)
                Text("Open Jaccuweather")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "cloud.sun.fill")
                    .font(.title2)
                    .foregroundStyle(accessory || renderingMode == .accented ? Color.primary : accent)
                    .widgetAccentable()
                Text("Open Jaccuweather")
                    .font(.headline)
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text("Refresh the app to fill this widget.")
                    .font(.caption)
                    .foregroundStyle(mutedColor)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
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
