import SwiftUI

struct HealthPollenView: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var plantsOpen = false

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        TabScreenScroll {
            if let weather = model.weather {
                // One stack, not a late first child of the screen's lazy stack.
                // Pollen arrives after the forecast, and a new row inserted above
                // the Health card stays offscreen at the current scroll offset.
                VStack(alignment: .leading, spacing: JWMetrics.sectionGap) {
                    todayCard(weather)
                    pollenCard
                }
            } else if let message = model.errorMessage, !message.isEmpty {
                Text(message)
                    .font(.body)
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("health-load-error")
            } else {
                Text("Load a location first.")
                    .font(.body)
                    .foregroundStyle(theme.muted)
            }
        }
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func todayCard(_ weather: WeatherBundle) -> some View {
        let health = model.health
        let nice = niceParts(health?.niceLine ?? "—")
        return WeatherCard(title: "Today", titleStyle: .section) {
            VStack(alignment: .leading, spacing: 0) {
                if let aqi = USAQIDisplay.from(current: model.pollen?.map("current")) {
                    airRow(aqi)
                    hairline
                }
                NavigationLink {
                    MethodologySheet(kind: .sinus, weather: weather, pollen: model.pollen)
                } label: {
                    scoreRow(
                        title: "Sinus",
                        symbol: "stethoscope",
                        value: health?.sinusLabel ?? "—",
                        detail: health?.sinusDetail ?? "",
                        tint: tone(health?.sinusLabel ?? "")
                    )
                }
                .buttonStyle(.plain)
                hairline
                NavigationLink {
                    MethodologySheet(kind: .allergy, weather: weather, pollen: model.pollen)
                } label: {
                    scoreRow(
                        title: "Allergy",
                        icon: "pollen",
                        value: health?.allergyLabel ?? "—",
                        detail: allergyDetail(health),
                        tint: tone(health?.allergyLabel ?? "")
                    )
                }
                .buttonStyle(.plain)
                hairline
                NavigationLink {
                    MethodologySheet(kind: .nice, weather: weather, pollen: model.pollen)
                } label: {
                    scoreRow(
                        title: "Nice Weather",
                        icon: "clear-day",
                        value: nice.score,
                        detail: nice.label,
                        tint: tone(nice.label.isEmpty ? nice.score : nice.label)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var pollenCard: some View {
        WeatherCard(title: "Pollen", titleStyle: .section) {
            if let pollen = model.pollen {
                let current = pollen.map("current")
                let categories = currentCategories(current, pollen: pollen)
                let days = LogicEngine.shared.pollenForecastDays(pollen)
                let dayWords = days.flatMap(dayLabels)
                let reported = PollenReading.worstLabel(categories.map(\.label) + dayWords) != nil
                if reported {
                    reportedPollen(categories, days: days, pollen: pollen)
                } else {
                    unreportedPollen(pollen)
                }
            } else {
                Text(model.pollenPending ? "Loading pollen…" : "Pollen is unavailable for this place right now.")
                    .font(.body)
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pollen-unavailable")
            }
        }
    }

    private func unreportedPollen(_ pollen: JSONMap) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing is reported for this place right now.")
                .font(.body)
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pollen-unreported")
            Text(sourceCaption(pollen.string("pollen_source")))
                .font(.caption)
                .foregroundStyle(theme.muted)
        }
    }

    private func reportedPollen(_ categories: [PollenCategory], days: [JSONMap], pollen: JSONMap) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let dominant = PollenReading.worstLabel(categories.map(\.label)) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Right now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.muted)
                    Spacer(minLength: 8)
                    Text(dominant)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(tone(dominant))
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Pollen right now, \(dominant)")
                categoryStrip(categories)
            } else {
                Text("Nothing reported right now.")
                    .font(.subheadline)
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !days.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("5-day")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.muted)
                    forecastBlock(days)
                }
            }

            plantsDisclosure(pollen.map("current"), pollen: pollen)

            Text(sourceCaption(pollen.string("pollen_source")))
                .font(.caption)
                .foregroundStyle(theme.muted)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(theme.divider)
            .frame(height: 1)
    }

    private func airRow(_ reading: USAQIDisplay) -> some View {
        let tint = JWTone.color(forAQI: reading.colorToken)
        return HStack(alignment: .center, spacing: 12) {
            SVGIconView(fileName: "smoke.svg", folder: "cards", pointSize: 22)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Air quality")
                    .font(.subheadline)
                    .foregroundStyle(theme.muted)
                Text(reading.category)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text("\(reading.value)")
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("air-quality-card")
        .accessibilityLabel("Air Quality \(reading.value), \(reading.category)")
    }

    private func scoreRow(title: String, symbol: String? = nil, icon: String? = nil, value: String, detail: String, tint: Color) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                scoreRowStack(title: title, symbol: symbol, icon: icon, value: value, detail: detail, tint: tint)
            } else {
                scoreRowBar(title: title, symbol: symbol, icon: icon, value: value, detail: detail, tint: tint)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.isEmpty ? "\(title), \(value)" : "\(title), \(value), \(detail)")
        .accessibilityHint("Shows how this score is calculated")
    }

    private func scoreRowBar(title: String, symbol: String? = nil, icon: String? = nil, value: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            tileIcon(symbol: symbol, icon: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.muted)
        }
    }

    private func scoreRowStack(title: String, symbol: String? = nil, icon: String? = nil, value: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                tileIcon(symbol: symbol, icon: icon)
                Text(title)
                    .font(.title3)
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.muted)
            }
            if !detail.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(detailLines(detail).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.body)
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Split "Weed pollen · Windy" so a wrapped separator is not left on its own line.
    private func detailLines(_ detail: String) -> [String] {
        let lines = detail
            .split(separator: "·", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? [detail] : lines
    }

    private func allergyDetail(_ health: CachedHealth?) -> String {
        guard let health else { return "" }
        if health.allergyLabel == "No data" { return "Pollen unavailable" }
        return health.allergyDetail
    }

    @ViewBuilder
    private func tileIcon(symbol: String? = nil, icon: String? = nil) -> some View {
        if let icon {
            SVGIconView(fileName: icon + ".svg", folder: "cards", pointSize: 22)
                .frame(width: 28, height: 28)
        } else if let symbol {
            // A font-sized symbol grows with Dynamic Type and paints outside a
            // fixed frame, covering the title. Draw it to a fixed box instead.
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(JWTone.blue)
                .frame(width: 28, height: 28)
        }
    }

    private func niceParts(_ line: String) -> (score: String, label: String) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[0].contains("/") { return (parts[0], parts[1]) }
        return (line, "")
    }

    private func tone(_ label: String) -> Color {
        switch label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "—", "-", "n/a", "none", "no data":
            return theme.muted
        default:
            return JWTone.color(forLabel: label)
        }
    }

    private struct PollenCategory: Identifiable {
        var id: String { name }
        var name: String
        var count: String
        var label: String
        var icon: String
    }

    private func currentCategories(_ current: JSONMap, pollen: JSONMap) -> [PollenCategory] {
        let tree = maxTree(current)
        let grass = current.number("grass_pollen")
        let weed = maxWeed(current)
        return [
            PollenCategory(name: "Tree", count: PollenReading.countText(tree), label: PollenReading.levelText(tree, nullAsNone: nullAsNone(pollen, ["alder_pollen", "birch_pollen", "olive_pollen", "tree_pollen"])), icon: "pollen-tree"),
            PollenCategory(name: "Grass", count: PollenReading.countText(grass), label: PollenReading.levelText(grass, nullAsNone: nullAsNone(pollen, ["grass_pollen"])), icon: "pollen-grass"),
            PollenCategory(name: "Weed", count: PollenReading.countText(weed), label: PollenReading.levelText(weed, nullAsNone: nullAsNone(pollen, ["weed_pollen", "mugwort_pollen", "ragweed_pollen"])), icon: "pollen-weed")
        ]
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

    @ViewBuilder
    private func categoryStrip(_ items: [PollenCategory]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(items) { item in
                    categoryColumn(item)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    categoryLine(item)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func categoryColumn(_ item: PollenCategory) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                SVGIconView(fileName: item.icon + ".svg", folder: "cards", pointSize: 16)
                    .frame(width: 16, height: 16)
                Text(item.name)
                    .font(.subheadline)
                    .foregroundStyle(theme.muted)
            }
            Text(item.count)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.text)
            Text(item.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tone(item.label))
                .fixedSize(horizontal: true, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name) \(item.count), \(item.label)")
    }

    private func categoryLine(_ item: PollenCategory) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.name)
                .foregroundStyle(theme.muted)
            Spacer(minLength: 8)
            Text(item.count)
                .foregroundStyle(theme.text)
            Text(item.label)
                .fontWeight(.semibold)
                .foregroundStyle(tone(item.label))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name) \(item.count), \(item.label)")
    }

    private func dayLabels(_ day: JSONMap) -> [String] {
        ["treeLabel", "grassLabel", "weedLabel"].map { day.string($0) ?? "n/a" }
    }

    @ViewBuilder
    private func forecastBlock(_ days: [JSONMap]) -> some View {
        ViewThatFits(in: .horizontal) {
            forecastGrid(days).fixedSize(horizontal: true, vertical: false)
            forecastStacked(days)
        }
    }

    private func forecastGrid(_ days: [JSONMap]) -> some View {
        Grid(alignment: .center, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                Text(" ")
                    .gridColumnAlignment(.leading)
                columnHeader("Tree")
                columnHeader("Grass")
                columnHeader("Weed")
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                let index = day.int("index") ?? 0
                let date = day.string("date") ?? ""
                let labels = dayLabels(day)
                GridRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(dayTitle(date, index: index))
                            .font(.subheadline.weight(.semibold))
                        Text(daySubtitle(date))
                            .font(.caption)
                            .foregroundStyle(theme.muted)
                    }
                    .fixedSize(horizontal: true, vertical: true)
                    .gridColumnAlignment(.leading)
                    levelText(labels[0])
                    levelText(labels[1])
                    levelText(labels[2])
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(dayTitle(date, index: index)), tree \(labels[0]), grass \(labels[1]), weed \(labels[2])")
            }
        }
    }

    private func columnHeader(_ name: String) -> some View {
        Text(name)
            .font(.caption)
            .foregroundStyle(theme.muted)
            .gridColumnAlignment(.center)
    }

    private func levelText(_ label: String) -> some View {
        Text(label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tone(label))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .fixedSize(horizontal: true, vertical: true)
            .gridColumnAlignment(.center)
    }

    private func forecastStacked(_ days: [JSONMap]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                let index = day.int("index") ?? 0
                let date = day.string("date") ?? ""
                let labels = dayLabels(day)
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayTitle(date, index: index))
                        .font(.subheadline.weight(.semibold))
                    Text(daySubtitle(date))
                        .font(.caption)
                        .foregroundStyle(theme.muted)
                    ForEach(Array(zip(["Tree", "Grass", "Weed"], labels)), id: \.0) { name, label in
                        HStack(alignment: .firstTextBaseline) {
                            Text(name)
                                .foregroundStyle(theme.muted)
                            Spacer(minLength: 8)
                            Text(label)
                                .fontWeight(.semibold)
                                .foregroundStyle(tone(label))
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.body)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(dayTitle(date, index: index)), tree \(labels[0]), grass \(labels[1]), weed \(labels[2])")
            }
        }
    }

    private func plantsDisclosure(_ current: JSONMap, pollen: JSONMap) -> some View {
        let fields = [
            ("Alder", "alder_pollen"),
            ("Birch", "birch_pollen"),
            ("Olive", "olive_pollen"),
            ("Mugwort", "mugwort_pollen"),
            ("Ragweed", "ragweed_pollen")
        ]
        return DisclosureGroup(isExpanded: $plantsOpen) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(fields, id: \.0) { name, key in
                    let value = current.number(key)
                    let label = PollenReading.levelText(value, nullAsNone: nullAsNone(pollen, [key]))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(name)
                            .foregroundStyle(theme.muted)
                        Spacer(minLength: 8)
                        Text(PollenReading.countText(value))
                            .foregroundStyle(theme.text)
                        Text(label)
                            .fontWeight(.semibold)
                            .foregroundStyle(tone(label))
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(name) \(PollenReading.countText(value)), \(label)")
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Plants")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.text)
        }
        .tint(theme.muted)
        .accessibilityIdentifier("pollen-plants")
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
