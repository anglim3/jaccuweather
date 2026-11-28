import SwiftUI
import WatchKit

/// One glance sheet. Day, hour, and alert details share it so they do not replace each other.
private enum WatchGlanceDetail: Identifiable {
    case day(WatchDaySlot)
    case hour(WatchHourSlot)
    case alert

    var id: String {
        switch self {
        case .day(let day): return "day-\(day.id)"
        case .hour(let hour): return "hour-\(hour.id)"
        case .alert: return "alert"
        }
    }
}

struct WatchGlanceView: View {
    var model: WatchWeatherModel
    @Environment(\.dynamicTypeSize) private var environmentTypeSize
    /// Launch override wins so a debug `-watchTextSize` preview matches Settings.
    private var dynamicTypeSize: DynamicTypeSize {
        WatchTextSizeLaunch.forced ?? environmentTypeSize
    }
    @State private var showPlaces = false
    @State private var closedLaunchList = false
    @State private var detail: WatchGlanceDetail?
    @State private var didPresentSampleDetail = false

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
            } else if WatchComplicationGalleryLaunch.requested {
                WatchComplicationGallery(snapshot: model.snapshot)
            } else {
                glance
            }
        }
        .preferredColorScheme(.dark)
        .modifier(WatchTextSizeLaunchModifier())
        .task { await model.start() }
        .onOpenURL { model.open($0) }
        .onAppear { presentSampleDetailIfNeeded() }
        .onChange(of: model.alert?.title) { _, _ in
            if model.alert == nil {
                if case .alert = detail { detail = nil }
            } else {
                presentSampleDetailIfNeeded()
            }
        }
    }

    /// Debug launches open the sheet once. A real badge tap sets `detail`.
    private func presentSampleDetailIfNeeded() {
        guard !didPresentSampleDetail, WatchAlertSample.presentsDetail, model.alert != nil, detail == nil else { return }
        didPresentSampleDetail = true
        detail = .alert
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

    /// Short face: wind and humidity on the sun line. UV only when both are missing.
    private var compactChips: [WatchAtmosphere.GlanceLine] {
        WatchAtmosphere.glanceChips(model.snapshot.atmosphereMetrics, roomy: false)
    }

    /// Roomy face: wind or UV, with humidity beside it when the forecast has it.
    private var roomyChips: [WatchAtmosphere.GlanceLine] {
        WatchAtmosphere.glanceChips(model.snapshot.atmosphereMetrics, roomy: true)
    }

    /// US AQI for the place on screen. Hidden when the reading is missing.
    private var aqiChip: WatchAQI.Chip? {
        WatchAQI.chip(usAqi: model.snapshot.usAqi, category: model.snapshot.usAqiCategory)
    }

    @ViewBuilder
    private func fittedStack(_ metrics: WatchGlanceMetrics) -> some View {
        let scaled = metrics.scaled(by: WatchTextScale.factor(dynamicTypeSize))
        let stack = glanceStack(scaled)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.bottom, metrics.bottomPadding)
            .padding(.top, WatchTextScale.needsRoom(dynamicTypeSize) ? 10 : 0)
        if WatchTextScale.needsRoom(dynamicTypeSize) {
            ScrollView(.vertical, showsIndicators: false) {
                stack
            }
        } else {
            stack
        }
    }

    private func glanceStack(_ metrics: WatchGlanceMetrics) -> some View {
        VStack(spacing: metrics.spacing) {
            placeTitle(metrics)
            HStack(alignment: .center, spacing: 6) {
                symbol(metrics)
                VStack(alignment: .leading, spacing: 0) {
                    readingCluster(metrics)
                    detailLine(metrics)
                }
            }
            if !metrics.foldsMetric, let aqi = aqiChip {
                WatchAQIChip(chip: aqi, compact: false)
            }
            if metrics.foldsMetric {
                if let sun = model.sun, sun.line != nil {
                    WatchSunRow(sun: sun, size: metrics.sunSize, chips: compactChips)
                } else if !compactChips.isEmpty {
                    WatchAtmosphereChips(chips: compactChips, size: metrics.sunSize)
                }
            } else {
                if let sun = model.sun, sun.line != nil {
                    WatchSunRow(sun: sun, size: metrics.sunSize)
                }
                if !roomyChips.isEmpty {
                    WatchAtmosphereChips(chips: roomyChips, size: metrics.sunSize)
                }
            }
            if let alert = model.alert {
                Button {
                    detail = .alert
                } label: {
                    WatchAlertBadge(alert: alert)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("watch-alert-badge")
                .accessibilityLabel(alert.spokenLabel)
                .accessibilityHint("Shows alert details")
            }
            WatchHourlyStrip(hours: model.hours, style: metrics.hourly) { hour in
                detail = .hour(hour)
            }
            WatchDailyStrip(days: model.days, style: metrics.daily) { day in
                detail = .day(day)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.accessibilityLabel)
        .sheet(item: $detail) { item in
            switch item {
            case .day(let day):
                WatchDayDetailView(day: day)
            case .hour(let hour):
                WatchHourDetailView(hour: hour)
            case .alert:
                if let alert = model.alert {
                    WatchAlertDetailSheet(alert: alert)
                }
            }
        }
        .onChange(of: model.days) { _, days in
            if case .day(let selected) = detail, let fresh = days.first(where: { $0.id == selected.id }), fresh != selected {
                detail = .day(fresh)
            }
            openLaunchDay(days)
        }
        .onChange(of: model.hours) { _, hours in
            if case .hour(let selected) = detail, let fresh = hours.first(where: { $0.id == selected.id }), fresh != selected {
                detail = .hour(fresh)
            }
            openLaunchHour(hours)
        }
    }

    /// Temperature beside the dew point. Large text stacks them when the row would collide.
    @ViewBuilder
    private func readingCluster(_ metrics: WatchGlanceMetrics) -> some View {
        if WatchTextScale.needsRoom(dynamicTypeSize) {
            ViewThatFits(in: .horizontal) {
                temperatureRow(metrics)
                VStack(alignment: .leading, spacing: 1) {
                    temperatureLabel(metrics)
                    dewChip(metrics)
                }
            }
        } else {
            temperatureRow(metrics)
        }
    }

    private func temperatureRow(_ metrics: WatchGlanceMetrics) -> some View {
        HStack(alignment: .center, spacing: 4) {
            temperatureLabel(metrics)
            dewChip(metrics)
        }
    }

    private func temperatureLabel(_ metrics: WatchGlanceMetrics) -> some View {
        Text(model.temperatureText)
            .font(WidgetHorizon.tempFont(size: metrics.tempSize))
            .foregroundStyle(WidgetHorizon.text)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .layoutPriority(1)
            .accessibilityLabel(WatchSpoken.degrees(fromDisplay: model.temperatureText))
    }

    @ViewBuilder
    private func dewChip(_ metrics: WatchGlanceMetrics) -> some View {
        if let dew = WatchDewPoint.chip(fahrenheit: model.snapshot.dewPointF) {
            WatchDewChip(chip: dew, compact: metrics.foldsMetric)
        }
    }

    /// Feels-like under the temperature when it differs by at least 2°F.
    /// Otherwise the condition occupies that same line, so a short face
    /// does not gain a row. The condition stays a second line only when
    /// the feels-like chip is visible and the hour strip is still empty.
    private func detailLine(_ metrics: WatchGlanceMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let chip = model.feelsChip {
                Text(chip.text)
                    .font(.system(size: metrics.detailSize, weight: .semibold))
                    .foregroundStyle(WidgetHorizon.accent)
                    .lineLimit(detailLineLimit)
                    .minimumScaleFactor(metrics.foldsMetric ? 0.5 : 0.7)
                    .accessibilityIdentifier("watch-feels")
                    .accessibilityLabel(chip.spoken)
            } else if !model.detailText.isEmpty {
                Text(model.detailText)
                    .font(.system(size: metrics.detailSize, weight: .semibold))
                    .foregroundStyle(WidgetHorizon.accent)
                    .lineLimit(detailLineLimit)
                    .minimumScaleFactor(metrics.foldsMetric ? 0.5 : 0.7)
            }
            if model.hours.isEmpty, !model.conditionText.isEmpty {
                Text(model.conditionText)
                    .font(.system(size: metrics.detailSize, weight: .medium))
                    .foregroundStyle(WidgetHorizon.text)
                    .lineLimit(detailLineLimit)
                    .minimumScaleFactor(metrics.foldsMetric ? 0.5 : 0.7)
            }
        }
    }

    /// `-watchDayDetail 1` opens the first place-local day once the strip has rows.
    private func openLaunchDay(_ days: [WatchDaySlot]) {
        #if DEBUG
        guard detail == nil, WatchDayDetailLaunch.opensFirst, let day = days.first else { return }
        detail = .day(day)
        #endif
    }

    /// `-watchHourDetail 1` opens the first place-local hour once the strip has rows.
    private func openLaunchHour(_ hours: [WatchHourSlot]) {
        #if DEBUG
        guard detail == nil, WatchHourDetailLaunch.opensFirst, let hour = hours.first else { return }
        detail = .hour(hour)
        #endif
    }

    @ViewBuilder
    private func placeTitle(_ metrics: WatchGlanceMetrics) -> some View {
        if WatchTextScale.needsRoom(dynamicTypeSize) {
            roomyPlaceTitle(metrics)
        } else if metrics.foldsMetric, let aqi = aqiChip {
            HStack(spacing: 2) {
                WatchAQIChip(chip: aqi, compact: true)
                    .layoutPriority(1)
                placeName(metrics)
                placesButton(metrics)
            }
        } else {
            ZStack {
                placeName(metrics)
                    .padding(.horizontal, 22)
                HStack {
                    Spacer(minLength: 0)
                    placesButton(metrics)
                }
            }
        }
    }

    /// Accessibility sizes keep the place name on the leading side. The system
    /// clock sits in the trailing corner, so that corner stays empty.
    private func roomyPlaceTitle(_ metrics: WatchGlanceMetrics) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 4) {
                placesButton(metrics)
                placeName(metrics)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if metrics.foldsMetric, let aqi = aqiChip {
                WatchAQIChip(chip: aqi, compact: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.trailing, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placeName(_ metrics: WatchGlanceMetrics) -> some View {
        Text(model.placeName)
            .font(WidgetHorizon.placeFont(size: metrics.placeSize))
            .foregroundStyle(WidgetHorizon.muted)
            .lineLimit(WatchTextScale.needsRoom(dynamicTypeSize) ? 2 : 1)
            .minimumScaleFactor(WatchTextScale.needsRoom(dynamicTypeSize) ? 0.7 : 0.6)
            .frame(
                maxWidth: .infinity,
                alignment: WatchTextScale.needsRoom(dynamicTypeSize) ? .leading : .center
            )
            .accessibilityIdentifier("watch-place")
    }

    private func placesButton(_ metrics: WatchGlanceMetrics) -> some View {
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
        .accessibilityHint("Shows saved places")
    }

    /// The condition is already written out when the feels-like line is absent,
    /// and when that line is showing but the hour strip has not arrived yet.
    private var speaksConditionInText: Bool {
        if model.feelsChip != nil {
            return model.hours.isEmpty && !model.conditionText.isEmpty
        }
        return !model.detailText.isEmpty && model.detailText != "Updating"
    }

    private var detailLineLimit: Int {
        WatchTextScale.needsRoom(dynamicTypeSize) ? 2 : 1
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
            .accessibilityLabel(model.snapshot.conditionText)
            .accessibilityHidden(speaksConditionInText || model.snapshot.conditionText.isEmpty)
    }
}

/// US AQI under the temperature on a roomy face, and beside the place name on a short one.
/// The color matches the iPhone Now and Health air-quality cards.
struct WatchAQIChip: View {
    var chip: WatchAQI.Chip
    var compact: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var tint: Color { WatchAQITint.color(for: chip.colorToken) }
    private var fontSize: CGFloat { (compact ? 9 : 11) * WatchTextScale.factor(dynamicTypeSize) }

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(tint)
                .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
                .accessibilityHidden(true)
            Text(chip.text)
            Text(chip.shortWord)
        }
        .font(.system(size: fontSize, weight: .semibold))
        .foregroundStyle(tint)
        .lineLimit(WatchTextScale.needsRoom(dynamicTypeSize) ? 2 : 1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, compact ? 1 : 2)
        .background {
            Capsule(style: .continuous)
                .fill(WidgetHorizon.glassStrong)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(tint.opacity(0.55), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("watch-aqi")
        .accessibilityLabel(chip.spoken)
    }
}

/// Dew point beside the temperature. Hidden when the reading is missing.
/// Stays off the sunrise line, which keeps wind and UV.
struct WatchDewChip: View {
    var chip: WatchDewPoint.Chip
    var compact: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var fontSize: CGFloat { (compact ? 9 : 11) * WatchTextScale.factor(dynamicTypeSize) }

    var body: some View {
        Text(chip.text)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(WidgetHorizon.text)
            .lineLimit(WatchTextScale.needsRoom(dynamicTypeSize) ? 2 : 1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, compact ? 4 : 5)
            .padding(.vertical, compact ? 1 : 2)
            .background {
                Capsule(style: .continuous)
                    .fill(WidgetHorizon.glassStrong)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(WidgetHorizon.glassBorder, lineWidth: 1)
                    }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("watch-dew")
            .accessibilityLabel(chip.spoken)
    }
}

enum WatchAQITint {
    static func color(for token: String) -> Color {
        switch token {
        case "green":
            return Color(red: 74 / 255, green: 222 / 255, blue: 128 / 255)
        case "yellow":
            return Color(red: 250 / 255, green: 204 / 255, blue: 21 / 255)
        case "orange":
            return Color(red: 251 / 255, green: 146 / 255, blue: 60 / 255)
        case "red":
            return Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255)
        case "purple":
            return Color(red: 192 / 255, green: 132 / 255, blue: 252 / 255)
        default:
            return Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)
        }
    }
}

/// Today's sunrise and sunset under the temperature.
/// On a short watch, wind and humidity share this line and scale together.
struct WatchSunRow: View {
    var sun: WatchSunTimes
    var size: CGFloat = 12
    var chips: [WatchAtmosphere.GlanceLine] = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if WatchTextScale.needsRoom(dynamicTypeSize), !chips.isEmpty {
                VStack(spacing: 1) {
                    clocks
                    WatchAtmosphereChipRow(chips: chips)
                }
            } else {
                line
            }
        }
        .font(.system(size: size, weight: .semibold))
        .monospacedDigit()
        .lineLimit(WatchTextScale.needsRoom(dynamicTypeSize) ? 2 : 1)
        .minimumScaleFactor(WatchTextScale.needsRoom(dynamicTypeSize) ? 0.65 : 0.45)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("watch-sun")
        .accessibilityLabel(spoken)
    }

    /// Clocks only, used when wind and humidity need their own line.
    private var clocks: Text {
        var parts: [Text] = []
        if let rise = sun.sunriseLabel {
            parts.append(Text("↑").foregroundStyle(WidgetHorizon.gold) + Text(" \(rise)").foregroundStyle(WidgetHorizon.text))
        }
        if let set = sun.sunsetLabel {
            parts.append(Text("↓").foregroundStyle(WidgetHorizon.gold) + Text(" \(set)").foregroundStyle(WidgetHorizon.text))
        }
        let dot = Text(" · ").foregroundStyle(WidgetHorizon.faint)
        return parts.dropFirst().reduce(parts.first ?? Text(""), { $0 + dot + $1 })
    }

    /// One run so the clocks, wind, and humidity shrink together instead of truncating.
    private var line: Text {
        var parts: [Text] = []
        if let rise = sun.sunriseLabel {
            parts.append(Text("↑").foregroundStyle(WidgetHorizon.gold) + Text(" \(rise)").foregroundStyle(WidgetHorizon.text))
        }
        if let set = sun.sunsetLabel {
            parts.append(Text("↓").foregroundStyle(WidgetHorizon.gold) + Text(" \(set)").foregroundStyle(WidgetHorizon.text))
        }
        for chip in chips {
            var chipText = Text("")
            if let symbol = chip.symbolName {
                chipText = chipText + Text(Image(systemName: symbol)).foregroundStyle(WidgetHorizon.accent) + Text(" ")
            }
            let color = chip.symbolName == nil ? WidgetHorizon.muted : WidgetHorizon.text
            chipText = chipText + Text(chip.text).foregroundStyle(color)
            parts.append(chipText)
        }
        let dot = Text(" · ").foregroundStyle(WidgetHorizon.faint)
        return parts.dropFirst().reduce(parts.first ?? Text(""), { $0 + dot + $1 })
    }

    private var spoken: String {
        var parts: [String] = []
        if !sun.spoken.isEmpty { parts.append(sun.spoken) }
        parts.append(contentsOf: chips.map(\.spoken))
        return parts.joined(separator: ", ")
    }
}

/// Wind, humidity, or UV on one line. Humidity draws a drop before the percent.
struct WatchAtmosphereChips: View {
    var chips: [WatchAtmosphere.GlanceLine]
    var size: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if WatchTextScale.needsRoom(dynamicTypeSize) {
                VStack(spacing: 1) {
                    ForEach(Array(chips.enumerated()), id: \.element.identifier) { _, chip in
                        WatchGlanceChipLabel(chip: chip)
                    }
                }
            } else {
                WatchAtmosphereChipRow(chips: chips)
            }
        }
        .font(.system(size: size, weight: .semibold))
        .monospacedDigit()
        .lineLimit(WatchTextScale.needsRoom(dynamicTypeSize) ? 2 : 1)
        .minimumScaleFactor(WatchTextScale.needsRoom(dynamicTypeSize) ? 0.65 : 0.5)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

struct WatchAtmosphereChipRow: View {
    var chips: [WatchAtmosphere.GlanceLine]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(chips.enumerated()), id: \.element.identifier) { index, chip in
                if index > 0 {
                    Text("·")
                        .foregroundStyle(WidgetHorizon.faint)
                        .accessibilityHidden(true)
                }
                WatchGlanceChipLabel(chip: chip)
            }
        }
    }
}

struct WatchGlanceChipLabel: View {
    var chip: WatchAtmosphere.GlanceLine

    var body: some View {
        HStack(spacing: 2) {
            if let symbol = chip.symbolName {
                Image(systemName: symbol)
                    .foregroundStyle(WidgetHorizon.accent)
                    .accessibilityHidden(true)
            }
            Text(chip.text)
                .foregroundStyle(chip.symbolName == nil ? WidgetHorizon.muted : WidgetHorizon.text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(chip.identifier)
        .accessibilityLabel(chip.spoken)
    }
}

/// Type and strip sizes for the glance. Shorter watches use the compact set
/// so the header, sun line, wind and humidity, and both strips stay on screen.
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
    /// Short watches put wind and humidity on the sun line instead of adding a row.
    var foldsMetric: Bool
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
        foldsMetric: false,
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
        foldsMetric: true,
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
    /// 1 at the default Dynamic Type size. Larger values opt into line boxes.
    var textScale: CGFloat = 1

    static let hourlyRegular = WatchStripStyle(
        columnWidth: 40, columnSpacing: 2, horizontalPadding: 6, verticalPadding: 4,
        labelSize: 11, primarySize: 14, secondarySize: 9, symbolSize: 9, cueHeight: 14, bandHeight: 56
    )
    static let hourlyCompact = WatchStripStyle(
        columnWidth: 36, columnSpacing: 2, horizontalPadding: 4, verticalPadding: 2,
        labelSize: 10, primarySize: 13, secondarySize: 9, symbolSize: 8, cueHeight: 12, bandHeight: 46
    )
    static let dailyRegular = WatchStripStyle(
        columnWidth: 42, columnSpacing: 2, horizontalPadding: 6, verticalPadding: 3,
        labelSize: 10, primarySize: 12, secondarySize: 9, symbolSize: 11, cueHeight: 13, bandHeight: 70
    )
    static let dailyCompact = WatchStripStyle(
        columnWidth: 36, columnSpacing: 2, horizontalPadding: 4, verticalPadding: 2,
        labelSize: 9, primarySize: 11, secondarySize: 9, symbolSize: 10, cueHeight: 12, bandHeight: 64
    )
}

/// How a forecast strip fills its card. Large faces grow columns so the next
/// one falls inside `trailingMask`. Narrow faces keep the preferred width so
/// the last full column (Monday, on a 40mm glance) stays on screen.
struct WatchStripColumns {
    var width: CGFloat
    var trailingMask: CGFloat
}

enum WatchStripLayout {
    static func columns(container: CGFloat, style: WatchStripStyle) -> WatchStripColumns {
        let pad = style.horizontalPadding
        let gap = style.columnSpacing
        let preferred = style.columnWidth
        guard container > 1, preferred > 1, gap >= 0 else {
            return WatchStripColumns(width: preferred, trailingMask: 0)
        }
        var count = 1
        while true {
            let next = count + 1
            let end = pad + CGFloat(next) * preferred + CGFloat(next - 1) * gap
            if end <= container + 0.5 {
                count = next
            } else {
                break
            }
        }
        let inner = container - pad * 2
        let grown = (inner - CGFloat(count - 1) * gap) / CGFloat(count)
        let width = max(preferred, grown)
        let nextStart = pad + CGFloat(count) * (width + gap)
        // Cover the peek, plus 1pt so a fractional column cannot show.
        let trailingMask = max(0, container - nextStart + 1)
        return WatchStripColumns(width: width, trailingMask: trailingMask)
    }
}

/// Current place plus the phone's favorites. Picking a row switches the glance.
struct WatchPlacesSheet: View {
    var model: WatchWeatherModel
    var onClose: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                                .lineLimit(WatchTextScale.needsRoom(dynamicTypeSize) ? 3 : 1)
                                .minimumScaleFactor(WatchTextScale.needsRoom(dynamicTypeSize) ? 0.8 : 0.7)
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
                    .accessibilityLabel(model.isSelected(place) ? "\(place.name), selected" : place.name)
                    .accessibilityAddTraits(model.isSelected(place) ? .isSelected : [])
                    .accessibilityHint("Shows weather for \(place.name)")
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var typeScale: CGFloat { WatchTextScale.factor(dynamicTypeSize) }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9 * typeScale, weight: .bold))
                .accessibilityHidden(true)
            Text(line)
                .font(.system(size: 10 * typeScale, weight: .semibold))
                .lineLimit(WatchTextScale.needsRoom(dynamicTypeSize) ? 3 : 1)
                .minimumScaleFactor(0.65)
        }
        .foregroundStyle(WatchAlertTint.color(for: alert.severity))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            Capsule(style: .continuous)
                .fill(WidgetHorizon.glassStrong)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(WatchAlertTint.color(for: alert.severity).opacity(0.55), lineWidth: 1)
                }
        }
        .accessibilityHidden(true)
    }

    private var line: String {
        if alert.count > 1 {
            return "\(alert.count) · \(alert.title)"
        }
        return alert.title
    }
}

enum WatchAlertTint {
    static func color(for severity: String) -> Color {
        switch severity.lowercased() {
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

/// Short alert sheet. Close returns to the glance. No extra glance chrome.
struct WatchAlertDetailSheet: View {
    var alert: WatchAlertSummary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var lines: WatchAlertDetailLines { alert.detailLines }
    private var compact: Bool { WKInterfaceDevice.current().screenBounds.height < 240 }
    private var typeScale: CGFloat { WatchTextScale.factor(dynamicTypeSize) }

    private func size(_ base: CGFloat) -> CGFloat { base * typeScale }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: size(compact ? 11 : 12), weight: .bold))
                            .accessibilityHidden(true)
                        Text("Close")
                            .font(.system(size: size(compact ? 12 : 13), weight: .semibold))
                    }
                    .foregroundStyle(WidgetHorizon.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watch-alert-close")
                .accessibilityLabel("Close")

                Text(lines.severity)
                    .font(.system(size: size(compact ? 11 : 12), weight: .bold))
                    .foregroundStyle(WatchAlertTint.color(for: lines.severity))
                    .textCase(.uppercase)
                    .accessibilityIdentifier("watch-alert-severity")
                    .accessibilityLabel(lines.severity)

                Text(lines.title)
                    .font(.system(size: size(compact ? 15 : 17), weight: .semibold))
                    .foregroundStyle(WidgetHorizon.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("watch-alert-title")

                if let headline = lines.headline {
                    Text(headline)
                        .font(.system(size: size(compact ? 12 : 13), weight: .medium))
                        .foregroundStyle(WidgetHorizon.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("watch-alert-headline")
                }

                Text(lines.countLine)
                    .font(.system(size: size(compact ? 12 : 13), weight: .semibold))
                    .foregroundStyle(WidgetHorizon.accent)
                    .accessibilityIdentifier("watch-alert-count")

                if let event = lines.event {
                    Text(event)
                        .font(.system(size: size(compact ? 12 : 13), weight: .medium))
                        .foregroundStyle(WidgetHorizon.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("watch-alert-event")
                }

                if let ends = lines.ends {
                    Text(ends)
                        .font(.system(size: size(compact ? 12 : 13), weight: .medium))
                        .foregroundStyle(WidgetHorizon.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("watch-alert-ends")
                }

                if let instruction = lines.instruction {
                    Text(instruction)
                        .font(.system(size: size(compact ? 12 : 13)))
                        .foregroundStyle(WidgetHorizon.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(WidgetHorizon.glass)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(WidgetHorizon.glassBorder, lineWidth: 1)
                                }
                        }
                        .accessibilityIdentifier("watch-alert-instruction")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, compact ? 2 : 4)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { WidgetHorizonBackground().ignoresSafeArea() }
        .accessibilityIdentifier("watch-alert-detail")
    }
}

/// Growth above the default Dynamic Type size. Large and smaller stay at 1
/// so the navy glass layout does not move. Accessibility sizes grow and scroll.
enum WatchTextScale {
    static func factor(_ size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall, .small, .medium, .large:
            return 1
        case .xLarge:
            return 1.12
        case .xxLarge:
            return 1.24
        case .xxxLarge:
            return 1.36
        case .accessibility1:
            return 1.48
        case .accessibility2:
            return 1.58
        case .accessibility3:
            return 1.68
        case .accessibility4:
            return 1.78
        case .accessibility5:
            return 1.9
        @unknown default:
            return size.isAccessibilitySize ? 1.7 : 1
        }
    }

    /// Accessibility sizes need a scroll and stacked rows. The default size does not.
    static func needsRoom(_ size: DynamicTypeSize) -> Bool {
        size.isAccessibilitySize
    }
}

/// Debug launches can preview the largest accessibility size with
/// `-watchTextSize accessibility5`. A normal launch uses the system size.
enum WatchTextSizeLaunch {
    static var forced: DynamicTypeSize? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-watchTextSize"), index + 1 < args.count else { return nil }
        switch args[index + 1].lowercased() {
        case "large", "default":
            return .large
        case "accessibility", "accessibility5", "ax5":
            return .accessibility5
        case "accessibility1", "ax1":
            return .accessibility1
        default:
            return nil
        }
        #else
        return nil
        #endif
    }
}

private struct WatchTextSizeLaunchModifier: ViewModifier {
    func body(content: Content) -> some View {
        if let forced = WatchTextSizeLaunch.forced {
            content.dynamicTypeSize(forced)
        } else {
            content
        }
    }
}

extension WatchGlanceMetrics {
    func scaled(by factor: CGFloat) -> WatchGlanceMetrics {
        guard factor > 1.001 else { return self }
        return WatchGlanceMetrics(
            placeSize: placeSize * factor,
            tempSize: tempSize * factor,
            detailSize: detailSize * factor,
            sunSize: sunSize * factor,
            symbolIcon: symbolIcon * min(factor, 1.45),
            symbolBox: symbolBox * min(factor, 1.45),
            placesIcon: placesIcon * min(factor, 1.5),
            placesHit: max(placesHit, placesHit * min(factor, 1.5)),
            spacing: spacing,
            horizontalPadding: horizontalPadding,
            bottomPadding: bottomPadding,
            foldsMetric: foldsMetric,
            hourly: hourly.scaled(by: factor),
            daily: daily.scaled(by: factor)
        )
    }
}

extension WatchStripStyle {
    func scaled(by factor: CGFloat) -> WatchStripStyle {
        guard factor > 1.001 else { return self }
        return WatchStripStyle(
            columnWidth: columnWidth * min(factor, 1.35),
            columnSpacing: columnSpacing,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            labelSize: labelSize * factor,
            primarySize: primarySize * factor,
            secondarySize: secondarySize * factor,
            symbolSize: symbolSize * min(factor, 1.5),
            cueHeight: cueHeight * min(factor, 1.6),
            bandHeight: bandHeight * factor,
            textScale: factor
        )
    }

    /// Default sizes keep the hand-tuned slack. Grown type uses a line box so
    /// the glyphs are not clipped inside the strip.
    func textBox(_ size: CGFloat, slack: CGFloat) -> CGFloat {
        let classic = size + slack
        guard textScale >= 1.4 else { return classic }
        return max(classic, ceil(size * 1.35))
    }
}
