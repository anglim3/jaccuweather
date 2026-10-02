import SwiftUI

struct HealthPollenView: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        TabScreenScroll {
            if let weather = model.weather {
                // One stack, not a late first child of the screen's lazy stack.
                // Pollen arrives after the forecast, and a new row inserted above
                // the Health card stays offscreen at the current scroll offset.
                VStack(alignment: .leading, spacing: JWMetrics.sectionGap) {
                let health = model.health
                if let aqi = USAQIDisplay.from(current: model.pollen?.map("current")) {
                    AirQualityCard(reading: aqi)
                }
                WeatherCard(title: "Health", titleStyle: .section) {
                    VStack(spacing: 10) {
                        NavigationLink {
                            MethodologySheet(kind: .sinus, weather: weather, pollen: model.pollen)
                        } label: {
                            scoreTile(
                                title: "Sinus",
                                symbol: "stethoscope",
                                value: health?.sinusLabel ?? "—",
                                detail: health?.sinusDetail ?? ""
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            MethodologySheet(kind: .allergy, weather: weather, pollen: model.pollen)
                        } label: {
                            scoreTile(
                                title: "Allergy",
                                icon: "pollen",
                                value: health?.allergyLabel ?? "—",
                                detail: health?.allergyDetail ?? ""
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            MethodologySheet(kind: .nice, weather: weather, pollen: model.pollen)
                        } label: {
                            niceTile(health?.niceLine ?? "—")
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let pollen = model.pollen {
                    let current = pollen.map("current")
                    let days = LogicEngine.shared.pollenForecastDays(pollen)
                    WeatherCard(title: "Pollen Forecast", titleStyle: .section) {
                        Text(sourceCaption(pollen.string("pollen_source")))
                            .font(.caption)
                            .foregroundStyle(theme.faint)

                        Text("Current Levels")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.muted)
                            .padding(.top, 4)

                        HStack(alignment: .top, spacing: 10) {
                            pollenCol("Tree", maxTree(current), "pollen-tree", nullAsNone: nullAsNone(pollen, ["alder_pollen", "birch_pollen", "olive_pollen", "tree_pollen"]))
                            pollenCol("Grass", current.number("grass_pollen"), "pollen-grass", nullAsNone: nullAsNone(pollen, ["grass_pollen"]))
                            pollenCol("Weed", maxWeed(current), "pollen-weed", nullAsNone: nullAsNone(pollen, ["weed_pollen", "mugwort_pollen", "ragweed_pollen"]))
                        }

                        if !days.isEmpty {
                            Text("5-Day Forecast")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.muted)
                                .padding(.top, 6)

                            VStack(spacing: 8) {
                                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                                    forecastRow(day)
                                }
                            }
                        }

                        speciesBlock(current, pollen: pollen)
                    }
                } else {
                    WeatherCard(title: "Pollen Forecast", titleStyle: .section) {
                        Text(model.pollenPending ? "Loading pollen…" : "Pollen is unavailable for this place right now.")
                            .font(JWFont.body)
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("pollen-unavailable")
                    }
                }
                }
            } else {
                Text("Load a location first.")
                    .foregroundStyle(theme.muted)
            }
        }
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func scoreTile(title: String, symbol: String? = nil, icon: String? = nil, value: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            tileIcon(symbol: symbol, icon: icon)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.muted)
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(theme.faint)
                }
                Text(value)
                    .font(JWFont.statValue)
                    .foregroundStyle(JWTone.color(forLabel: value))
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jwGlass(.stat)
        .accessibilityElement(children: .combine)
    }

    private func niceTile(_ line: String) -> some View {
        let parts = niceParts(line)
        return HStack(alignment: .center, spacing: 12) {
            tileIcon(icon: "clear-day")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Nice Weather")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.muted)
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(theme.faint)
                }
                Text(parts.score)
                    .font(JWFont.statValue)
                    .foregroundStyle(JWTone.color(forLabel: parts.label))
                if !parts.label.isEmpty {
                    Text(parts.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(JWTone.color(forLabel: parts.label))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jwGlass(.stat)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nice Weather \(line)")
    }

    @ViewBuilder
    private func tileIcon(symbol: String? = nil, icon: String? = nil) -> some View {
        if let icon {
            SVGIconView(fileName: icon + ".svg", folder: "cards", pointSize: 28)
                .frame(width: 32, height: 32)
        } else if let symbol {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(JWTone.blue)
                .frame(width: 32, height: 32)
        }
    }

    private func niceParts(_ line: String) -> (score: String, label: String) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[0].contains("/") { return (parts[0], parts[1]) }
        return (line, "")
    }

    private func maxTree(_ current: JSONMap) -> Double? {
        LogicEngine.shared.number("maxAvailablePollen", [[
            current.number("tree_pollen") as Any,
            current.number("alder_pollen") as Any,
            current.number("birch_pollen") as Any,
            current.number("olive_pollen") as Any
        ]])
    }

    private func maxWeed(_ current: JSONMap) -> Double? {
        LogicEngine.shared.number("maxAvailablePollen", [[
            current.number("weed_pollen") as Any,
            current.number("mugwort_pollen") as Any,
            current.number("ragweed_pollen") as Any
        ]])
    }

    private func nullAsNone(_ pollen: JSONMap, _ fields: [String]) -> Bool {
        let flags = pollen.map("pollen_null_display_as_none").map("current")
        return fields.contains { flags.bool($0) }
    }

    private func pollenLevel(_ value: Double?, nullAsNone: Bool) -> (text: String, color: Color) {
        let label = PollenReading.levelText(value, nullAsNone: nullAsNone)
        return (label, JWTone.color(forLabel: label))
    }

    private func speciesBlock(_ current: JSONMap, pollen: JSONMap) -> some View {
        let fields = [
            ("Alder", "alder_pollen"),
            ("Birch", "birch_pollen"),
            ("Olive", "olive_pollen"),
            ("Mugwort", "mugwort_pollen"),
            ("Ragweed", "ragweed_pollen")
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(theme.divider)
                .frame(height: 1)
                .padding(.top, 4)
            Text("Tree: Alder, Birch, Olive  ·  Grass  ·  Weed: Mugwort, Ragweed")
                .font(.caption2)
                .foregroundStyle(theme.faint)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(fields, id: \.0) { name, key in
                let value = current.number(key)
                let level = pollenLevel(value, nullAsNone: nullAsNone(pollen, [key]))
                HStack {
                    Text(name)
                    Spacer(minLength: 8)
                    Text(PollenReading.countText(value))
                        .foregroundStyle(theme.text)
                    Text(level.text)
                        .foregroundStyle(level.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(minWidth: 36, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(theme.muted)
            }
        }
    }

    private func pollenCol(_ name: String, _ value: Double?, _ icon: String, nullAsNone: Bool) -> some View {
        let level = pollenLevel(value, nullAsNone: nullAsNone)
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                SVGIconView(fileName: icon + ".svg", folder: "cards", pointSize: 22)
                    .frame(width: 22, height: 22)
                Text(name)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(PollenReading.countText(value))
                .font(.system(size: 20, weight: .bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(level.text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(level.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .jwGlass(.stat)
    }

    private func forecastRow(_ day: JSONMap) -> some View {
        let index = day.int("index") ?? 0
        let date = day.string("date") ?? ""
        return HStack(alignment: .center, spacing: 10) {
            Text(day.string("emoji") ?? "🌿")
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(dayTitle(date, index: index))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(daySubtitle(date))
                    .font(.caption2)
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            forecastCol("Tree", day.string("treeLabel"))
            forecastCol("Grass", day.string("grassLabel"))
            forecastCol("Weed", day.string("weedLabel"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .jwGlass(.stat)
    }

    private func forecastCol(_ name: String, _ label: String?) -> some View {
        let text = label ?? "—"
        return VStack(spacing: 2) {
            Text(name)
                .font(.caption2)
                .foregroundStyle(theme.faint)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(JWTone.color(forLabel: text))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(minWidth: 52, maxWidth: 76)
    }

    private func dayTitle(_ date: String, index: Int) -> String {
        if index == 0 { return "Today" }
        if index == 1 { return "Tomorrow" }
        guard let parsed = Self.dayParser.date(from: date) else { return date }
        return Self.weekday.string(from: parsed)
    }

    private func daySubtitle(_ date: String) -> String {
        guard let parsed = Self.dayParser.date(from: date) else { return date }
        return Self.monthDay.string(from: parsed)
    }

    private func sourceCaption(_ raw: String?) -> String {
        switch raw?.lowercased() {
        case "google": return "Source · Google"
        case "tomorrow", "tomorrow.io": return "Source · Tomorrow.io"
        case "open-meteo", nil, "": return "Source · Open-Meteo"
        default: return "Source · \(raw!)"
        }
    }

    private static let dayParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter
    }()

    private static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()
}

struct AirQualityCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let reading: USAQIDisplay
    var compact: Bool = false

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }
    private var tint: Color { JWTone.color(forAQI: reading.colorToken) }

    var body: some View {
        Group {
            if compact { compactBody } else { healthBody }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(compact ? "now-air-quality" : "air-quality-card")
        .accessibilityLabel("Air Quality \(reading.value), \(reading.category)")
    }

    private var healthBody: some View {
        WeatherCard(title: "Air Quality", titleStyle: .section) {
            HStack(alignment: .center, spacing: 14) {
                SVGIconView(fileName: "smoke.svg", folder: "cards", pointSize: 36)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(reading.value)")
                        .font(JWFont.statValue)
                        .foregroundStyle(tint)
                    Text(reading.category)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var compactBody: some View {
        HStack(spacing: 12) {
            SVGIconView(fileName: "smoke.svg", folder: "cards", pointSize: 28)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Air Quality")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.muted)
                Text(reading.category)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text("\(reading.value)")
                .font(JWFont.statValue)
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jwGlass(.stat)
    }
}
