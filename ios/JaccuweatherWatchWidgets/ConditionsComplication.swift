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
        .description("Temperature and condition for the Watch's place, with precipitation chance on circular and corner.")
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
    /// Set by the debug gallery. The widget leaves this nil and uses the slot WidgetKit provides.
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var environmentFamily

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

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
                .font(.system(size: precipText == nil ? 14 : 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .widgetAccentable()
            Text(degreesText)
                .font(.caption.weight(.bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .widgetAccentable()
            if let precipText {
                HStack(spacing: 2) {
                    Image(systemName: precipSymbol)
                        .font(.system(size: 8, weight: .bold))
                    Text(precipText)
                        .font(.system(size: 10, weight: .bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .foregroundStyle(WidgetHorizon.accent)
                .widgetAccentable()
                .accessibilityIdentifier("watch-complication-precip")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenWithPrecip)
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
    /// The longer form adds the chance. Faces that clip it keep the shorter lines.
    private var inline: some View {
        ViewThatFits(in: .horizontal) {
            Label(inlineWithPrecip, systemImage: symbol)
            Label(inlineLine, systemImage: symbol)
            Label(degreesText, systemImage: symbol)
            Text(degreesText)
        }
        .lineLimit(1)
        .widgetAccentable()
        .accessibilityLabel(spokenWithPrecip)
    }

    /// Corner disk is the temperature. The curved label is the condition,
    /// with its SF Symbol, along the bezel. A meaningful chance is added to
    /// that label. The gallery is not on a bezel, so it draws the same words.
    private var corner: some View {
        VStack(spacing: 1) {
            Text(degreesText)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .widgetAccentable()
            if familyOverride != nil {
                cornerLabelView
                    .font(.system(size: 9, weight: .semibold))
                    .minimumScaleFactor(0.5)
            }
        }
        .widgetLabel {
            cornerLabelView
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenWithPrecip)
    }

    private var cornerLabelView: some View {
        Label(cornerLabel, systemImage: symbol)
            .lineLimit(1)
            .widgetAccentable()
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

    private var precipText: String? {
        WatchComplicationCopy.precipText(
            chance: entry.snapshot.precipChance,
            weatherCode: entry.snapshot.weatherCode
        )
    }

    private var precipSymbol: String {
        WatchComplicationCopy.precipSymbol(weatherCode: entry.snapshot.weatherCode)
    }

    private var cornerLabel: String {
        WatchComplicationCopy.cornerLabel(
            conditionText: entry.snapshot.conditionText,
            feelsLikeF: entry.snapshot.feelsLikeF,
            precipChance: entry.snapshot.precipChance,
            weatherCode: entry.snapshot.weatherCode
        )
    }

    private var inlineWithPrecip: String {
        WatchComplicationCopy.inlineWithPrecip(
            temperatureF: entry.snapshot.temperatureF,
            conditionText: entry.snapshot.conditionText,
            feelsLikeF: entry.snapshot.feelsLikeF,
            precipChance: entry.snapshot.precipChance,
            weatherCode: entry.snapshot.weatherCode
        )
    }

    /// Temperature and condition, plus the chance when this slot shows it.
    /// The rectangular slot keeps `spoken`, so its line stays the condition.
    private var spokenWithPrecip: String {
        guard let extra = WatchComplicationCopy.precipSpoken(
            chance: entry.snapshot.precipChance,
            weatherCode: entry.snapshot.weatherCode
        ) else { return spoken }
        return "\(spoken), \(extra)"
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

