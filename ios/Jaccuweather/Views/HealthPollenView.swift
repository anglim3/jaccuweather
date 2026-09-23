import SwiftUI

struct HealthPollenView: View {
    @Environment(WeatherViewModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WeatherCard(title: "Health") {
                    HStack(spacing: 12) {
                        riskTile("Sinus", model.sinus?.label ?? "—", model.sinus?.detail ?? "Need forecast")
                        riskTile("Allergy", model.allergy.label, model.allergy.detail)
                    }
                    Text("Nice-weather index is not ported yet (needs the full hourly averaging from public/app.js).")
                        .font(.caption)
                        .foregroundStyle(JWTheme.muted)
                }

                WeatherCard(title: "Air + pollen") {
                    if let pollen = model.pollen {
                        LabeledContent("Source", value: pollen.source)
                        if let aqi = pollen.usAqi {
                            LabeledContent("US AQI", value: "\(Int(aqi.rounded())) · \(HealthScores.aqiCategory(aqi))")
                        } else {
                            Text("AQI is empty when the source is Google/Tomorrow. Open-Meteo supplies US AQI.")
                                .font(.caption)
                                .foregroundStyle(JWTheme.muted)
                        }
                        pollenRow("Grass", pollen.grassPollen)
                        pollenRow("Weed", pollen.weedPollen)
                        pollenRow("Tree (category)", pollen.treePollen)
                        pollenRow("Alder", pollen.alderPollen)
                        pollenRow("Birch", pollen.birchPollen)
                        pollenRow("Olive", pollen.olivePollen)
                        pollenRow("Ragweed", pollen.ragweedPollen)
                        if pollen.daily.isEmpty == false {
                            Divider().padding(.vertical, 4)
                            Text("5-day")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(JWTheme.muted)
                            ForEach(pollen.daily) { day in
                                HStack {
                                    Text(String(day.time.prefix(10)))
                                    Spacer()
                                    Text(day.grass.map { String(format: "%.0f", $0) } ?? "—")
                                        .foregroundStyle(JWTheme.muted)
                                }
                                .font(.caption)
                            }
                        }
                    } else {
                        Text("No pollen payload. Open-Meteo is used when Google/Tomorrow keys are empty.")
                            .foregroundStyle(JWTheme.muted)
                    }
                    Text("Paid keys: fill Config/Secrets.xcconfig locally. Empty keys keep the Open-Meteo fallback.")
                        .font(.caption2)
                        .foregroundStyle(JWTheme.muted)
                        .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .background(JWTheme.background.ignoresSafeArea())
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func riskTile(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(JWTheme.muted)
            Text(value)
                .font(.title2.weight(.bold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(JWTheme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func pollenRow(_ name: String, _ value: Double?) -> some View {
        LabeledContent(name, value: value.map { String(format: "%.0f", $0) } ?? "n/a")
    }
}
