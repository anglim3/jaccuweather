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
        let place = Self.chosenPlace(configuration)
        let stored = WidgetSnapshotStore.load()
        if let stored, WidgetTimelineLoader.snapshotBelongsToWidget(stored, place: place) {
            return ConditionsEntry(date: Date(), snapshot: stored, unavailablePlaceName: nil)
        }
        if context.isPreview {
            let sample = place.map(WidgetConditionsSnapshot.preview(for:)) ?? .gallery
            return ConditionsEntry(date: Date(), snapshot: sample, unavailablePlaceName: nil)
        }
        if let place {
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
        let loaded = await WidgetTimelineLoader.load(place: Self.chosenPlace(configuration))
        let entry = ConditionsEntry(
            date: Date(),
            snapshot: loaded.snapshot,
            unavailablePlaceName: loaded.unavailablePlaceName
        )
        let interval: TimeInterval = loaded.snapshot == nil ? 5 * 60 : 20 * 60
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(interval)))
    }

    /// The place from Edit Widget. Debug builds can also read a JSON stand-in
    /// while the App Group container is forced off.
    static func chosenPlace(_ configuration: PlaceWidgetIntent) -> WidgetPlace? {
        if let place = configuration.place { return place }
        #if DEBUG
        return WidgetPlace.debugOverride()
        #else
        return nil
        #endif
    }
}

enum WidgetTimelineLoader {
    struct Loaded {
        var snapshot: WidgetConditionsSnapshot?
        var unavailablePlaceName: String?
    }

    /// A fresh App Group snapshot is used only when it is this widget's place,
    /// or when the widget has no chosen place and follows the app.
    /// A different chosen place is loaded from Open-Meteo, which is also the
    /// Personal Team path when the container is missing.
    static func load(place: WidgetPlace?) async -> Loaded {
        let stored = WidgetSnapshotStore.load()
        let matches = stored.map { snapshotBelongsToWidget($0, place: place) } ?? false
        switch WidgetTimelinePlan.decide(
            hasSnapshot: stored != nil,
            snapshotFresh: stored?.isFresh ?? false,
            hasConfiguredPlace: place != nil,
            snapshotMatchesPlace: matches
        ) {
        case .useSnapshot:
            return Loaded(snapshot: stored, unavailablePlaceName: nil)
        case .fetchConfiguredPlace:
            if let place,
               let fetched = await WidgetCurrentRefresh.fetch(
                   name: place.name,
                   latitude: place.latitude,
                   longitude: place.longitude,
                   locationId: place.id
               ) {
                return Loaded(snapshot: fetched, unavailablePlaceName: nil)
            }
            return await finish(stored: stored, place: place, matches: matches, fetchFailed: true)
        case .refreshSnapshot:
            return await finish(stored: stored, place: place, matches: matches, fetchFailed: false)
        case .keepStaleSnapshot, .unavailable, .empty:
            if let place {
                return Loaded(snapshot: nil, unavailablePlaceName: place.name)
            }
            return Loaded(snapshot: nil, unavailablePlaceName: nil)
        }
    }

    /// The snapshot belongs to this widget when there is no chosen place, or the coordinates match.
    static func snapshotBelongsToWidget(_ stored: WidgetConditionsSnapshot, place: WidgetPlace?) -> Bool {
        guard let place else { return true }
        return WidgetTimelinePlan.samePlace(
            snapshotLatitude: stored.latitude,
            snapshotLongitude: stored.longitude,
            snapshotLocationId: stored.locationId,
            placeLatitude: place.latitude,
            placeLongitude: place.longitude,
            placeId: place.id
        )
    }

    private static func finish(
        stored: WidgetConditionsSnapshot?,
        place: WidgetPlace?,
        matches: Bool,
        fetchFailed: Bool
    ) async -> Loaded {
        let refreshPlan = fetchFailed
            ? WidgetTimelinePlan.afterFailedFetch(
                hasSnapshot: stored != nil,
                snapshotMatchesPlace: matches,
                hasConfiguredPlace: place != nil
            )
            : WidgetTimelinePlan.refreshSnapshot
        if refreshPlan == .refreshSnapshot, let stored {
            if let refreshed = await WidgetCurrentRefresh.refresh(stored) {
                WidgetSnapshotStore.save(refreshed, reloadWidgets: false)
                return Loaded(snapshot: refreshed, unavailablePlaceName: nil)
            }
            let stalePlan = WidgetTimelinePlan.afterFailedRefresh(
                hasConfiguredPlace: place != nil,
                withinStaleWindow: stored.age < WidgetConditionsSnapshot.showStaleUntil
            )
            if stalePlan == .keepStaleSnapshot {
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
        .description("Temperature and sky for a place you choose. A fresh reading from the app is used when it is that place.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct ConditionsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    var entry: ConditionsEntry

    private var accessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        default:
            return false
        }
    }

    /// Full-color home widgets, and any accessory context that still paints a background.
    private var fullColor: Bool {
        showsBackground && renderingMode == .fullColor && family != .accessoryInline
    }

    private var titleColor: Color {
        fullColor ? WidgetHorizon.text : .primary
    }

    private var mutedColor: Color {
        fullColor ? WidgetHorizon.muted : .secondary
    }

    private var accentColor: Color {
        fullColor ? WidgetHorizon.accent : .primary
    }

    private var contentPadding: EdgeInsets {
        switch family {
        case .systemSmall:
            return EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        case .systemMedium:
            return EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        case .accessoryRectangular:
            return EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4)
        default:
            return EdgeInsets()
        }
    }

    var body: some View {
        content
            .padding(contentPadding)
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
        case .accessoryInline:
            Color.clear
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                WidgetHorizonBackground()
            }
        default:
            WidgetHorizonBackground()
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
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.locationName)
                .font(WidgetHorizon.placeFont(size: 15))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .center, spacing: 6) {
                Text(degrees(snapshot.temperatureF))
                    .font(WidgetHorizon.tempFont(size: 42))
                    .tracking(-1.4)
                    .foregroundStyle(titleColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .widgetAccentable()
                Spacer(minLength: 0)
                symbolBadge(snapshot.symbolName, diameter: 36)
            }
            if !snapshot.conditionText.isEmpty {
                Text(snapshot.conditionText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            summaryBar(snapshot)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(snapshot))
    }

    private func medium(_ snapshot: WidgetConditionsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.locationName)
                .font(WidgetHorizon.placeFont(size: 17))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .center, spacing: 8) {
                Text(degrees(snapshot.temperatureF))
                    .font(WidgetHorizon.tempFont(size: 36))
                    .tracking(-1.4)
                    .foregroundStyle(titleColor)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .widgetAccentable()
                if !snapshot.conditionText.isEmpty {
                    Text(snapshot.conditionText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                symbolBadge(snapshot.symbolName, diameter: 36)
            }
            chipRow(snapshot)
            if !snapshot.nextHoursHint.isEmpty {
                Text(snapshot.nextHoursHint)
                    .font(.caption2)
                    .foregroundStyle(fullColor ? WidgetHorizon.faint : mutedColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(snapshot))
    }

    private func circular(_ snapshot: WidgetConditionsSnapshot) -> some View {
        VStack(spacing: 1) {
            symbolBadge(snapshot.symbolName, diameter: 20, icon: 15)
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
            symbolBadge(snapshot.symbolName, diameter: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.locationName)
                    .font(WidgetHorizon.placeFont(size: 12))
                    .foregroundStyle(mutedColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(degrees(snapshot.temperatureF))
                    .font(WidgetHorizon.tempFont(size: 22))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                Text(detailLine(snapshot))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(mutedColor)
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
                symbolBadge("mappin.and.ellipse", diameter: 32)
                Text("Choose a place")
                    .font(WidgetHorizon.placeFont(size: 17))
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
                    .font(WidgetHorizon.placeFont(size: 15))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                Text("Couldn't load weather")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Couldn't load weather for \(name)")
        }
    }

    private func symbolBadge(_ name: String, diameter: CGFloat, icon: CGFloat? = nil) -> some View {
        Image(systemName: name)
            .font(.system(size: icon ?? diameter * 0.56, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(accentColor)
            .widgetAccentable()
            .frame(width: diameter, height: diameter)
            .background {
                if fullColor {
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
                                    endRadius: diameter * 0.72
                                )
                            )
                        }
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func summaryBar(_ snapshot: WidgetConditionsSnapshot) -> some View {
        let bits = summaryBits(snapshot)
        if !bits.isEmpty {
            WidgetGlassLabel(
                text: bits.joined(separator: "   "),
                fullColor: fullColor,
                foreground: fullColor ? WidgetHorizon.text : mutedColor
            )
        }
    }

    @ViewBuilder
    private func chipRow(_ snapshot: WidgetConditionsSnapshot) -> some View {
        let bits = chipBits(snapshot)
        if !bits.isEmpty {
            HStack(spacing: 6) {
                ForEach(bits, id: \.self) { bit in
                    WidgetGlassLabel(text: bit, fullColor: fullColor, foreground: titleColor)
                }
            }
            .lineLimit(1)
        }
    }

    private func summaryBits(_ snapshot: WidgetConditionsSnapshot) -> [String] {
        var bits: [String] = []
        if snapshot.highF != nil {
            bits.append("H \(degrees(snapshot.highF))")
        }
        if snapshot.lowF != nil {
            bits.append("L \(degrees(snapshot.lowF))")
        }
        if let chance = snapshot.precipChance {
            bits.append("\(chance)%")
        }
        return bits
    }

    private func chipBits(_ snapshot: WidgetConditionsSnapshot) -> [String] {
        var bits: [String] = []
        if snapshot.feelsLikeF != nil {
            bits.append("Feels \(degrees(snapshot.feelsLikeF))")
        }
        bits.append(contentsOf: summaryBits(snapshot))
        return bits
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
        CurrentConditionsLiveActivity()
        if #available(iOS 18.0, *) {
            OpenNowControl()
        }
    }
}
