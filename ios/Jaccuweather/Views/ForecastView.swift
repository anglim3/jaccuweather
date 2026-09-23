import SwiftUI
import Charts

struct ForecastView: View {
    @Environment(WeatherViewModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WeatherCard(title: "Next 48 hours") {
                    if model.hourlyPoints.isEmpty {
                        Text("Load a location to see hourly temperatures.")
                            .foregroundStyle(JWTheme.muted)
                    } else {
                        Chart(model.hourlyPoints) { point in
                            if let temperature = point.temperature {
                                LineMark(
                                    x: .value("Time", point.time),
                                    y: .value("Temp", temperature)
                                )
                                .foregroundStyle(JWTheme.accent)
                                .interpolationMethod(.catmullRom)
                            }
                        }
                        .chartXAxis(.hidden)
                        .frame(height: 160)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(model.hourlyPoints.prefix(24)) { point in
                                    VStack(spacing: 6) {
                                        Text(hourLabel(point.time))
                                            .font(.caption2)
                                            .foregroundStyle(JWTheme.muted)
                                        Image(systemName: WeatherCode.symbol(code: point.weatherCode))
                                            .foregroundStyle(JWTheme.accent)
                                        Text(point.temperature.map { "\(Int($0.rounded()))°" } ?? "—")
                                            .font(.subheadline.weight(.semibold))
                                        if let chance = point.precipChance {
                                            Text("\(chance)%")
                                                .font(.caption2)
                                                .foregroundStyle(JWTheme.muted)
                                        }
                                    }
                                    .frame(width: 52)
                                }
                            }
                        }
                    }
                }

                WeatherCard(title: "14-day") {
                    VStack(spacing: 0) {
                        ForEach(model.dailyPoints) { day in
                            HStack {
                                Text(dayLabel(day.date))
                                    .frame(width: 92, alignment: .leading)
                                Image(systemName: WeatherCode.symbol(code: day.weatherCode))
                                    .frame(width: 28)
                                    .foregroundStyle(JWTheme.accent)
                                Spacer()
                                Text(day.precip.map { String(format: "%.2f in", $0) } ?? "")
                                    .font(.caption)
                                    .foregroundStyle(JWTheme.muted)
                                    .frame(width: 64, alignment: .trailing)
                                Text(day.low.map { "\(Int($0.rounded()))°" } ?? "—")
                                    .foregroundStyle(JWTheme.muted)
                                    .frame(width: 36, alignment: .trailing)
                                Text(day.high.map { "\(Int($0.rounded()))°" } ?? "—")
                                    .fontWeight(.semibold)
                                    .frame(width: 40, alignment: .trailing)
                            }
                            .padding(.vertical, 8)
                            if day.id != model.dailyPoints.last?.id {
                                Divider().background(JWTheme.cardStroke)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(JWTheme.background.ignoresSafeArea())
        .navigationTitle("Forecast")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hourLabel(_ stamp: String) -> String {
        let part = stamp.split(separator: "T").last.map(String.init) ?? stamp
        return String(part.prefix(5))
    }

    private func dayLabel(_ date: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let parsed = formatter.date(from: date) else { return date }
        formatter.dateFormat = "EEE MMM d"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: parsed)
    }
}
