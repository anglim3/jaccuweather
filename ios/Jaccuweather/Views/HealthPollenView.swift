import SwiftUI

struct HealthPollenView: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        TabScreenScroll {
            if let weather = model.weather {
                let health = model.health
                WeatherCard(title: "Scores") {
                    NavigationLink { MethodologySheet(kind: .sinus, weather: weather, pollen: model.pollen) } label: {
                        scoreRow("Sinus", health?.sinusLabel ?? "—", health?.sinusDetail ?? "")
                    }
                    NavigationLink { MethodologySheet(kind: .allergy, weather: weather, pollen: model.pollen) } label: {
                        scoreRow("Allergy", health?.allergyLabel ?? "—", health?.allergyDetail ?? "")
                    }
                    NavigationLink { MethodologySheet(kind: .nice, weather: weather, pollen: model.pollen) } label: {
                        scoreRow("Nice weather", health?.niceLine ?? "—", "Same scoring as the website")
                    }
                }

                    if let pollen = model.pollen {
                        let current = pollen.map("current")
                        WeatherCard(title: "Pollen · \(pollen.string("pollen_source") ?? "open-meteo")") {
                            HStack {
                                pollenCol("Tree", maxTree(current), "pollen-tree")
                                pollenCol("Grass", current.number("grass_pollen"), "pollen-grass")
                                pollenCol("Weed", maxWeed(current), "pollen-weed")
                            }
                            speciesBlock(current)
                        }

                        let days = LogicEngine.shared.pollenForecastDays(pollen)
                        if !days.isEmpty {
                            WeatherCard(title: "5-day pollen forecast") {
                                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                                    HStack {
                                        Text(day.string("emoji") ?? "🌿")
                                        VStack(alignment: .leading) {
                                            Text(dayLabel(day.string("date") ?? "", index: day.int("index") ?? 0))
                                                .font(.subheadline.weight(.semibold))
                                            Text(day.string("date") ?? "").font(.caption2).foregroundStyle(theme.muted)
                                        }
                                        Spacer()
                                        forecastCol("Tree", day.string("treeLabel"))
                                        forecastCol("Grass", day.string("grassLabel"))
                                        forecastCol("Weed", day.string("weedLabel"))
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    } else {
                        WeatherCard(title: "Pollen") {
                            Text("Open-Meteo fallback (blank Google/Tomorrow keys).").foregroundStyle(theme.muted)
                        }
                    }
                } else {
                    Text("Load a location first.").foregroundStyle(theme.muted)
                }
        }
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.inline)
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

    private func speciesBlock(_ current: JSONMap) -> some View {
        let fields = [
            ("Alder", "alder_pollen"),
            ("Birch", "birch_pollen"),
            ("Olive", "olive_pollen"),
            ("Mugwort", "mugwort_pollen"),
            ("Ragweed", "ragweed_pollen")
        ]
        return VStack(alignment: .leading, spacing: 6) {
            Text("Species detail (Google plantInfo when keyed; otherwise n/a / Open-Meteo)")
                .font(.caption)
                .foregroundStyle(theme.muted)
            ForEach(fields, id: \.0) { name, key in
                let value = current.number(key)
                HStack {
                    Text(name)
                    Spacer()
                    Text(LogicEngine.shared.string("formatPollenValue", [value as Any]) ?? "n/a")
                    Text(JSONMap(LogicEngine.shared.object("getPollenLevel", [value as Any])).string("label") ?? "")
                        .foregroundStyle(theme.muted)
                }
                .font(.caption)
            }
        }
        .padding(.top, 8)
    }

    private func pollenCol(_ name: String, _ value: Double?, _ icon: String) -> some View {
        let level = JSONMap(LogicEngine.shared.object("getPollenLevel", [value as Any]))
        return VStack {
            SVGIconView(fileName: icon + ".svg", folder: "cards", pointSize: 22).frame(width: 22, height: 22)
            Text(name).font(.caption).foregroundStyle(theme.muted)
            Text(LogicEngine.shared.string("formatPollenValue", [value as Any]) ?? "n/a").font(.headline)
            Text(level.string("label") ?? "None").font(.caption2)
        }
        .frame(maxWidth: .infinity)
    }

    private func forecastCol(_ name: String, _ label: String?) -> some View {
        VStack {
            Text(name).font(.caption2).foregroundStyle(theme.muted)
            Text(label ?? "—").font(.caption.weight(.semibold))
        }
        .frame(width: 52)
    }

    private func dayLabel(_ date: String, index: Int) -> String {
        if index == 0 { return "Today" }
        if index == 1 { return "Tomorrow" }
        return date
    }

    private func scoreRow(_ title: String, _ value: String, _ detail: String) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.caption).foregroundStyle(theme.muted)
                Text(value).font(.title3.weight(.bold))
                Text(detail).font(.caption).foregroundStyle(theme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(theme.muted)
        }
        .padding(.vertical, 6)
    }
}
