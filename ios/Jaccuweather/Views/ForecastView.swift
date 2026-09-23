import SwiftUI
import Charts

struct ForecastView: View {
    @Environment(WeatherViewModel.self) private var model
    @State private var hourlyMode = "conditions"
    @State private var dailySeries = "temp"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Hourly", selection: $hourlyMode) {
                    Text("Conditions").tag("conditions")
                    Text("Precip").tag("precip")
                    Text("Wind").tag("wind")
                    Text("UV").tag("uv")
                    Text("Humidity").tag("humidity")
                    Text("Pressure").tag("pressure")
                    if model.tides != nil { Text("Tides").tag("tides") }
                }
                .pickerStyle(.segmented)

                WeatherCard(title: "Next 48 hours") {
                    chart48
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.hourlyRows) { row in
                                hourlyChip(row)
                            }
                        }
                    }
                }

                Picker("14-day series", selection: $dailySeries) {
                    Text("Temp").tag("temp")
                    Text("Precip").tag("precip")
                    Text("UV").tag("uv")
                    Text("Wind").tag("wind")
                    Text("Cloud").tag("cloud")
                }
                .pickerStyle(.segmented)

                WeatherCard(title: "14-day") {
                    dailyChart
                    ForEach(model.dailyRows) { day in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(day.label).frame(width: 92, alignment: .leading)
                                SVGIconView(fileName: day.iconFile, folder: "weather", pointSize: 28)
                                    .frame(width: 28, height: 28)
                                Spacer()
                                Text(day.precipChance.map { "\($0)%" } ?? "")
                                    .font(.caption).foregroundStyle(JWTheme.muted).frame(width: 36, alignment: .trailing)
                                Text(day.uv.map { String(format: "UV %.0f", $0) } ?? "")
                                    .font(.caption).foregroundStyle(JWTheme.muted)
                                Text(int(day.low)).foregroundStyle(JWTheme.muted).frame(width: 32, alignment: .trailing)
                                Text(int(day.high)).fontWeight(.semibold).frame(width: 36, alignment: .trailing)
                            }
                            HStack {
                                Text(LogicEngine.shared.weatherDescription(day.code))
                                if let feels = day.feelsHigh {
                                    Text("Feels \(Int(feels.rounded()))°")
                                }
                                if let rise = day.sunrise {
                                    Text(LogicEngine.shared.string("formatIsoLocalClock", [rise]) ?? "")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(JWTheme.muted)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(16)
        }
        .background(JWTheme.background.ignoresSafeArea())
        .navigationTitle("Forecast")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var chart48: some View {
        if hourlyMode == "tides", let tides = model.tides {
            Chart(Array(tides.curve.prefix(192))) { point in
                LineMark(x: .value("t", point.time), y: .value("ft", point.value))
                    .foregroundStyle(JWTheme.accent)
                    .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .frame(height: 150)
        } else {
            Chart(model.hourlyRows) { row in
                switch hourlyMode {
                case "precip":
                    BarMark(x: .value("t", row.clock), y: .value("p", row.precip ?? 0)).foregroundStyle(JWTheme.accent)
                case "wind":
                    LineMark(x: .value("t", row.clock), y: .value("w", row.wind ?? 0)).foregroundStyle(JWTheme.accent)
                case "uv":
                    LineMark(x: .value("t", row.clock), y: .value("u", row.uv ?? 0)).foregroundStyle(JWTheme.gold)
                case "humidity":
                    LineMark(x: .value("t", row.clock), y: .value("h", row.humidity ?? 0)).foregroundStyle(JWTheme.accent)
                case "pressure":
                    LineMark(x: .value("t", row.clock), y: .value("p", row.pressure ?? 0)).foregroundStyle(JWTheme.muted)
                default:
                    LineMark(x: .value("t", row.clock), y: .value("temp", row.temp ?? 0))
                        .foregroundStyle(JWTheme.accent)
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 150)
        }
    }

    @ViewBuilder
    private var dailyChart: some View {
        Chart(model.dailyRows) { day in
            switch dailySeries {
            case "precip":
                BarMark(x: .value("d", day.label), y: .value("p", day.precip ?? 0)).foregroundStyle(JWTheme.accent)
            case "uv":
                LineMark(x: .value("d", day.label), y: .value("u", day.uv ?? 0)).foregroundStyle(JWTheme.gold)
            case "wind":
                LineMark(x: .value("d", day.label), y: .value("w", day.wind ?? 0)).foregroundStyle(JWTheme.accent)
            case "cloud":
                LineMark(x: .value("d", day.label), y: .value("c", cloudFor(day) ?? 0)).foregroundStyle(.white.opacity(0.7))
            default:
                LineMark(x: .value("d", day.label), y: .value("h", day.high ?? 0)).foregroundStyle(.orange)
                LineMark(x: .value("d", day.label), y: .value("l", day.low ?? 0)).foregroundStyle(JWTheme.accent)
            }
        }
        .chartXAxis(.hidden)
        .frame(height: 150)
    }

    private func hourlyChip(_ row: HourRow) -> some View {
        VStack(spacing: 6) {
            Text(row.clock).font(.caption2).foregroundStyle(JWTheme.muted)
            SVGIconView(fileName: row.iconFile, folder: "weather", pointSize: 28).frame(width: 28, height: 28)
            switch hourlyMode {
            case "precip":
                Text(row.precip.map { String(format: "%.2f\"", $0) } ?? "0\"").font(.caption.weight(.semibold))
                Text(row.precipChance.map { "\($0)%" } ?? "").font(.caption2).foregroundStyle(JWTheme.muted)
            case "wind":
                Text(row.wind.map { String(format: "%.0f", $0) } ?? "—").font(.caption.weight(.semibold))
            case "uv":
                Text(row.uv.map { String(format: "%.0f", $0) } ?? "—").font(.caption.weight(.semibold))
                Text(row.uv.map { LogicEngine.shared.uvLabel($0) } ?? "").font(.caption2).foregroundStyle(JWTheme.muted)
            case "humidity":
                Text(row.humidity.map { "\(Int($0.rounded()))%" } ?? "—").font(.caption.weight(.semibold))
            case "pressure":
                Text(row.pressure.map { String(format: "%.0f", $0) } ?? "—").font(.caption.weight(.semibold))
            default:
                Text(row.temp.map { "\(Int($0.rounded()))°" } ?? "—").font(.caption.weight(.semibold))
            }
        }
        .frame(width: 56)
    }

    private func cloudFor(_ day: DayRow) -> Double? {
        guard let weather = model.weather else { return nil }
        return LogicEngine.shared.number("getAverageHourlyValueForDate", [weather.hourly.raw, "cloud_cover", day.date])
    }

    private func int(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))°"
    }
}
