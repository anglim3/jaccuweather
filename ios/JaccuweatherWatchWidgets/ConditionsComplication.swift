import SwiftUI
import WidgetKit

struct WatchComplicationEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetConditionsSnapshot
}

struct WatchConditionsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchMirror.complicationKind, provider: WatchComplicationProvider()) { entry in
            WatchComplicationView(entry: entry)
        }
        .configurationDisplayName("Conditions")
        .description("Temperature and condition for the last place.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct WatchComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchComplicationEntry {
        WatchComplicationEntry(date: Date(), snapshot: WatchMirror.placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchComplicationEntry) -> Void) {
        if context.isPreview {
            completion(WatchComplicationEntry(date: Date(), snapshot: WatchMirror.placeholder))
            return
        }
        Task {
            let snapshot = await WatchConditionsLoader.load(phoneContext: [:])
            completion(WatchComplicationEntry(date: Date(), snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchComplicationEntry>) -> Void) {
        Task {
            let snapshot = await WatchConditionsLoader.load(phoneContext: [:])
            let entry = WatchComplicationEntry(date: Date(), snapshot: snapshot)
            let next = Date().addingTimeInterval(20 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct WatchComplicationView: View {
    var entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                WidgetHorizonBackground()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        default:
            circular
        }
    }

    private var circular: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .widgetAccentable()
            Text(degrees)
                .font(.caption.weight(.bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .widgetAccentable()
        }
        .accessibilityLabel(spoken)
    }

    private var rectangular: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .widgetAccentable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.snapshot.locationName)
                    .font(WidgetHorizon.placeFont(size: 12))
                    .foregroundStyle(WidgetHorizon.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(degrees)
                    .font(WidgetHorizon.tempFont(size: 20))
                    .foregroundStyle(WidgetHorizon.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                Text(condition)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WidgetHorizon.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var symbol: String {
        entry.snapshot.symbolName.isEmpty ? "cloud.fill" : entry.snapshot.symbolName
    }

    private var degrees: String {
        guard let value = entry.snapshot.temperatureF, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))°"
    }

    private var condition: String {
        if !entry.snapshot.conditionText.isEmpty { return entry.snapshot.conditionText }
        if let feels = entry.snapshot.feelsLikeF, feels.isFinite {
            return "Feels \(Int(feels.rounded()))°"
        }
        return "Conditions"
    }

    private var spoken: String {
        let place = entry.snapshot.locationName.isEmpty ? "Jaccuweather" : entry.snapshot.locationName
        return "\(place), \(degrees), \(condition)"
    }
}

@main
struct JaccuweatherWatchWidgets: WidgetBundle {
    var body: some Widget {
        WatchConditionsComplication()
    }
}
