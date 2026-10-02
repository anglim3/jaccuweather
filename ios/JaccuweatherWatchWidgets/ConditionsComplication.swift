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
        .description("Temperature and condition for the Watch's place.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

struct WatchComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchComplicationEntry {
        #if DEBUG
        WatchPlaceStore.writeProbe(role: "placeholder")
        #endif
        return WatchComplicationEntry(date: Date(), snapshot: Self.sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchComplicationEntry) -> Void) {
        if context.isPreview {
            completion(WatchComplicationEntry(date: Date(), snapshot: Self.sample()))
            return
        }
        Task {
            let snapshot = await Self.reading()
            completion(WatchComplicationEntry(date: Date(), snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchComplicationEntry>) -> Void) {
        Task {
            let snapshot = await Self.reading()
            let entry = WatchComplicationEntry(date: Date(), snapshot: snapshot)
            let next = Date().addingTimeInterval(20 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private static func reading() async -> WidgetConditionsSnapshot {
        let reading = await WatchConditionsLoader.load(phoneContext: [:], publishPlace: false)
        #if DEBUG
        WatchPlaceStore.writeProbe(role: "complication")
        #endif
        return reading.snapshot
    }

    /// Gallery sample until the glance has published a place. After that, the
    /// sample city is not shown.
    private static func sample() -> WidgetConditionsSnapshot {
        let shared = WatchPlaceStore.load()
        if let saved = WatchMirrorStore.load(), saved.temperatureF != nil {
            if let shared {
                if WatchPlacePlan.same(saved.placeChoice, shared.choice(hasReading: false)) {
                    return saved
                }
            } else {
                return saved
            }
        }
        if let shared {
            return shared.shell()
        }
        return WatchMirror.placeholder
    }
}

struct WatchComplicationView: View {
    var entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(WatchPlaceLink.url(for: WatchPlace(entry.snapshot)))
            .containerBackground(for: .widget) { plate }
    }

    /// Circular and rectangular keep the navy plate. Inline and corner take
    /// the watch face tint, so a filled plate would cover the face color.
    @ViewBuilder
    private var plate: some View {
        switch family {
        case .accessoryInline:
            Color.clear
        case .accessoryCorner:
            AccessoryWidgetBackground()
        default:
            WidgetHorizonBackground()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            inline
        case .accessoryCorner:
            corner
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
            Text(degreesText)
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
                Text(degreesText)
                    .font(WidgetHorizon.tempFont(size: 20))
                    .foregroundStyle(WidgetHorizon.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                Text(conditionText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WidgetHorizon.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// One line above the clock: symbol, temperature, then the condition.
    /// The temperature-only forms are for faces that clip the longer line.
    private var inline: some View {
        ViewThatFits(in: .horizontal) {
            Label(inlineLine, systemImage: symbol)
            Label(degreesText, systemImage: symbol)
            Text(degreesText)
        }
        .lineLimit(1)
        .widgetAccentable()
        .accessibilityLabel(spoken)
    }

    /// Corner disk is the temperature. The curved label is the condition,
    /// with its SF Symbol, along the bezel.
    private var corner: some View {
        Text(degreesText)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .widgetAccentable()
            .widgetLabel {
                Label(conditionText, systemImage: symbol)
                    .widgetAccentable()
            }
            .accessibilityLabel(spoken)
    }

    private var symbol: String {
        WatchComplicationCopy.symbol(named: entry.snapshot.symbolName)
    }

    private var degreesText: String {
        WatchComplicationCopy.degrees(temperatureF: entry.snapshot.temperatureF)
    }

    private var conditionText: String {
        WatchComplicationCopy.condition(
            conditionText: entry.snapshot.conditionText,
            feelsLikeF: entry.snapshot.feelsLikeF
        )
    }

    private var inlineLine: String {
        WatchComplicationCopy.inlineLine(
            temperatureF: entry.snapshot.temperatureF,
            conditionText: entry.snapshot.conditionText,
            feelsLikeF: entry.snapshot.feelsLikeF
        )
    }

    private var spoken: String {
        let place = entry.snapshot.locationName.isEmpty ? "Jaccuweather" : entry.snapshot.locationName
        return "\(place), \(degreesText), \(conditionText)"
    }
}

@main
struct JaccuweatherWatchWidgets: WidgetBundle {
    var body: some Widget {
        WatchConditionsComplication()
    }
}
