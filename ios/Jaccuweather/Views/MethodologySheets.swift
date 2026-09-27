import SwiftUI

struct MethodologySheet: View {
    enum Kind { case sinus, allergy, nice }
    let kind: Kind
    let weather: WeatherBundle
    let pollen: JSONMap?
    @Environment(\.colorScheme) private var colorScheme

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JWMetrics.sectionGap) {
                switch kind {
                case .sinus:
                    let sinus = HealthScores.sinus(from: weather)
                    Text(sinus.label)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(JWTone.color(forLabel: sinus.label))
                    if !sinus.detail.isEmpty {
                        Text(sinus.detail).foregroundStyle(theme.muted)
                    }
                    noteCard("Falling pressure is the main driver. Humid or rainy conditions and large day-night temperature swings add to it.")
                    detailCard(title: "Pressure", symbol: "arrow.down", tint: JWTone.blue) {
                        bullet("Steady")
                        bullet("Falling")
                        bullet("Falling fast")
                    }
                    detailCard(title: "Humidity and temperature", symbol: "drop.fill", tint: JWTone.blue) {
                        Text("Humid, rain, or a swing over 20°F.")
                            .font(.subheadline)
                            .foregroundStyle(theme.muted)
                    }
                    detailCard(title: "Scoring", symbol: "list.bullet", tint: theme.accent) {
                        Text("Falling +2. Falling fast +3. Humid, rain, or swing over 20°F: +1.")
                        Text("0–1 Low · 2 Elevated · 3–4 High.")
                    }
                case .allergy:
                    let allergy = HealthScores.allergy(pollen: pollen, weather: weather)
                    Text(allergy.label)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(JWTone.color(forLabel: allergy.label))
                    if !allergy.detail.isEmpty {
                        Text(allergy.detail).foregroundStyle(theme.muted)
                    }
                    noteCard("Follows the highest pollen count: tree, grass, or weed.")
                    detailCard(title: "Pollen", icon: "pollen", tint: JWTone.green) {
                        bullet("None / Low", result: "Low", resultColor: JWTone.green)
                        bullet("Moderate", result: "Elevated", resultColor: JWTone.yellow)
                        bullet("High / Very high", result: "High", resultColor: JWTone.orange)
                    }
                    detailCard(title: "Wind and rain", symbol: "wind", tint: JWTone.green) {
                        Text("Wind spreads pollen. Rain washes it out. Neither changes the score.")
                            .font(.subheadline)
                            .foregroundStyle(theme.muted)
                    }
                    detailCard(title: "Scoring", symbol: "list.bullet", tint: theme.accent) {
                        Text("Grains/m³: 0–20 Low · 20–80 Moderate · 80–200 High · 200+ Very high.")
                    }
                case .nice:
                    let nice = HealthScores.niceWeather(from: weather)
                    Text(nice.score.map { "\($0)/10" } ?? "—")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(JWTone.color(forLabel: nice.label))
                    Text(nice.label)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(JWTone.color(forLabel: nice.label))
                    Text("Current Components")
                        .font(JWFont.section)
                    ForEach(Array(nice.factors.enumerated()), id: \.offset) { _, factor in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(factor.string("name") ?? "")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(factor.string("value") ?? "")
                                    .font(.subheadline)
                                Text("\(factor.int("points") ?? 0) pts")
                                    .font(.caption)
                                    .foregroundStyle(theme.muted)
                            }
                            Text(factor.string("note") ?? "")
                                .font(.caption)
                                .foregroundStyle(theme.muted)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .jwGlass(.stat)
                    }
                    noteCard("The Nice Weather index starts at 10 and subtracts points for conditions that make outdoor weather less comfortable.")
                }
                Text("Estimates only, not medical advice.")
                    .font(.caption2)
                    .foregroundStyle(theme.faint)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
            .font(.subheadline)
            .foregroundStyle(theme.text)
        }
        .scrollContentBackground(.hidden)
        .jwScreenChrome()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func noteCard(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .jwGlass(.stat)
    }

    private func detailCard<Content: View>(title: String, symbol: String? = nil, icon: String? = nil, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let icon {
                    SVGIconView(fileName: icon + ".svg", folder: "cards", pointSize: 18)
                        .frame(width: 20, height: 20)
                } else if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            content()
                .font(.subheadline)
                .foregroundStyle(theme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jwGlass(.stat)
    }

    private func bullet(_ text: String, result: String? = nil, resultColor: Color = .white) -> some View {
        HStack(spacing: 6) {
            Text("•")
            Text(text).foregroundStyle(theme.text)
            if let result {
                Text("→").foregroundStyle(theme.faint)
                Text(result)
                    .fontWeight(.semibold)
                    .foregroundStyle(resultColor)
            }
        }
    }

    private var title: String {
        switch kind {
        case .sinus: return "Sinus"
        case .allergy: return "Allergy"
        case .nice: return "Nice Weather"
        }
    }
}

struct MoonSheet: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        let moon = model.moon
        NavigationStack {
            VStack(spacing: 16) {
                Text(moon.emoji).font(.system(size: 72))
                Text(moon.name).font(.title.bold())
                LabeledContent("Moonrise", value: moon.rise)
                LabeledContent("Moonset", value: moon.set)
                LabeledContent("Illumination", value: moon.illumination)
                LabeledContent("Next full", value: moon.nextFull)
                LabeledContent("Next new", value: moon.nextNew)
                Text("Times use the location timezone offset from Open-Meteo (utc_offset_seconds), matching SunCalc + formatInstantInLocation on the website.")
                    .font(.caption)
                    .foregroundStyle(theme.muted)
                Spacer()
            }
            .padding(24)
            .navigationTitle("Moon")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
