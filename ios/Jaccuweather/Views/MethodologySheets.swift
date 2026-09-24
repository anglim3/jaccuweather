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
            VStack(alignment: .leading, spacing: 16) {
                switch kind {
                case .sinus:
                    let sinus = HealthScores.sinus(from: weather)
                    Text(sinus.label).font(.largeTitle.bold())
                    Text(sinus.detail).foregroundStyle(theme.muted)
                    Text("Falling pressure is the main driver. Humid or rainy conditions and large day-night temperature swings add to it.")
                    Text("Scoring: Falling +2. Falling fast +3. Humid, rain, or swing over 20°F: +1. 0–1 Low · 2 Elevated · 3–4 High.")
                        .font(.caption)
                        .foregroundStyle(theme.muted)
                case .allergy:
                    let allergy = HealthScores.allergy(pollen: pollen, weather: weather)
                    Text(allergy.label).font(.largeTitle.bold())
                    Text(allergy.detail).foregroundStyle(theme.muted)
                    Text("Follows the highest pollen count: tree, grass, or weed. Wind and rain are shown but do not change the score.")
                    Text("Grains/m³: 0–20 Low · 20–80 Moderate · 80–200 High · 200+ Very high.")
                        .font(.caption)
                        .foregroundStyle(theme.muted)
                case .nice:
                    let nice = HealthScores.niceWeather(from: weather)
                    Text(nice.score.map { "\($0)/10" } ?? "—").font(.largeTitle.bold())
                    Text(nice.label)
                    ForEach(Array(nice.factors.enumerated()), id: \.offset) { _, factor in
                        HStack {
                            Text(factor.string("name") ?? "")
                            Spacer()
                            Text(factor.string("value") ?? "")
                            Text("\(factor.int("points") ?? 0) pts").foregroundStyle(theme.muted)
                        }
                        Text(factor.string("note") ?? "").font(.caption).foregroundStyle(theme.muted)
                    }
                }
                Text("Estimates only, not medical advice.").font(.caption2).foregroundStyle(theme.muted)
            }
            .padding(20)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        switch kind {
        case .sinus: return "Sinus methodology"
        case .allergy: return "Allergy methodology"
        case .nice: return "Nice-weather methodology"
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
