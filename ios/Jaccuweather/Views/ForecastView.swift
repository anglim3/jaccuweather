import SwiftUI
import Charts

struct ForecastView: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var hourlyMode = LaunchArgs.hourly
    @State private var dailySeries = LaunchArgs.daily

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        TabScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Hourly", selection: $hourlyMode) {
                    Text("Conditions").tag("conditions")
                    Text("Precip").tag("precip")
                    Text("Wind").tag("wind")
                    Text("UV").tag("uv")
                    Text("Humidity").tag("humidity")
                    Text("Pressure").tag("pressure")
                    Text("Cloud").tag("cloud")
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
                                    .font(.caption).foregroundStyle(theme.muted).frame(width: 36, alignment: .trailing)
                                Text(day.uv.map { String(format: "UV %.0f", $0) } ?? "")
                                    .font(.caption).foregroundStyle(theme.muted)
                                Text(int(day.low)).foregroundStyle(theme.muted).frame(width: 32, alignment: .trailing)
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
                            .foregroundStyle(theme.muted)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Forecast")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if LaunchArgs.value("hourly") != nil { hourlyMode = LaunchArgs.hourly }
            if LaunchArgs.value("daily") != nil { dailySeries = LaunchArgs.daily }
        }
    }

    @ViewBuilder
    private var chart48: some View {
        if hourlyMode == "tides", let tides = model.tides {
            Chart(Array(tides.curve.prefix(192))) { point in
                LineMark(x: .value("t", point.time), y: .value("ft", point.value))
                    .foregroundStyle(theme.accent)
                    .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .frame(height: 150)
        } else if hourlyMode == "cloud" {
            cloudChart(samples: hourlyCloudSamples, showXAxis: true)
        } else if hourlyMode == "wind" {
            Chart(model.hourlyRows) { row in
                LineMark(x: .value("t", row.time), y: .value("mph", row.wind ?? 0))
                    .foregroundStyle(by: .value("series", "Speed"))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("t", row.time), y: .value("mph", row.windGust ?? 0))
                    .foregroundStyle(by: .value("series", "Gust"))
                    .interpolationMethod(.catmullRom)
            }
            .chartForegroundStyleScale(["Speed": theme.accent, "Gust": theme.gold])
            .chartLegend(position: .bottom)
            .chartYAxisLabel("mph")
            .modifier(ForecastAxisStyle(theme: theme, labeledX: true))
            .frame(height: 200)
        } else {
            Chart(model.hourlyRows) { row in
                switch hourlyMode {
                case "precip":
                    BarMark(x: .value("t", row.time), y: .value("p", row.precip ?? 0)).foregroundStyle(theme.accent)
                case "uv":
                    LineMark(x: .value("t", row.time), y: .value("u", row.uv ?? 0)).foregroundStyle(theme.gold)
                case "humidity":
                    LineMark(x: .value("t", row.time), y: .value("h", row.humidity ?? 0)).foregroundStyle(theme.accent)
                case "pressure":
                    LineMark(x: .value("t", row.time), y: .value("p", (row.pressure ?? 0) * 0.02953)).foregroundStyle(theme.muted)
                default:
                    LineMark(x: .value("t", row.time), y: .value("temp", row.temp ?? 0))
                        .foregroundStyle(theme.accent)
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartYAxisLabel(hourlyUnit)
            .modifier(ForecastAxisStyle(theme: theme, labeledX: true))
            .frame(height: 180)
        }
    }

    @ViewBuilder
    private var dailyChart: some View {
        if dailySeries == "cloud" {
            cloudChart(samples: dailyCloudSamples, showXAxis: false)
        } else {
            Chart(model.dailyRows) { day in
                switch dailySeries {
                case "precip":
                    BarMark(x: .value("d", day.label), y: .value("p", day.precip ?? 0)).foregroundStyle(theme.accent)
                case "uv":
                    LineMark(x: .value("d", day.label), y: .value("u", day.uv ?? 0)).foregroundStyle(theme.gold)
                case "wind":
                    LineMark(x: .value("d", day.label), y: .value("w", day.wind ?? 0)).foregroundStyle(theme.accent)
                default:
                    LineMark(x: .value("d", day.label), y: .value("h", day.high ?? 0)).foregroundStyle(.orange)
                    LineMark(x: .value("d", day.label), y: .value("l", day.low ?? 0)).foregroundStyle(theme.accent)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(theme.grid)
                    AxisValueLabel().foregroundStyle(theme.muted)
                }
            }
            .chartYAxisLabel(dailyUnit)
            .frame(height: 180)
        }
        if dailySeries == "temp" {
            HStack(spacing: 16) {
                Label("High", systemImage: "circle.fill").foregroundStyle(.orange)
                Label("Low", systemImage: "circle.fill").foregroundStyle(theme.accent)
            }
            .font(.caption2)
            .padding(.top, 4)
        }
    }

    private func hourlyChip(_ row: HourRow) -> some View {
        VStack(spacing: 6) {
            Text(row.clock).font(.caption2).foregroundStyle(theme.muted)
            if hourlyMode != "wind" {
                SVGIconView(fileName: row.iconFile, folder: "weather", pointSize: 28).frame(width: 28, height: 28)
            }
            switch hourlyMode {
            case "precip":
                Text(row.precip.map { String(format: "%.2f\"", $0) } ?? "0\"").font(.caption.weight(.semibold))
                Text(row.precipChance.map { "\($0)%" } ?? "").font(.caption2).foregroundStyle(theme.muted)
            case "wind":
                if let dir = row.windDir {
                    Image(systemName: "location.north.fill")
                        .font(.caption)
                        .rotationEffect(.degrees(WindCompass.arrowDegrees(dir)))
                        .accessibilityLabel("From \(WindCompass.label(dir))")
                }
                Text(row.wind.map { String(format: "%.0f", $0) } ?? "—").font(.caption.weight(.semibold))
                Text(row.windGust.map { String(format: "mph G%.0f", $0) } ?? "mph")
                    .font(.caption2)
                    .foregroundStyle(theme.muted)
            case "uv":
                Text(row.uv.map { String(format: "%.0f", $0) } ?? "—").font(.caption.weight(.semibold))
                Text(row.uv.map { LogicEngine.shared.uvLabel($0) } ?? "").font(.caption2).foregroundStyle(theme.muted)
            case "humidity":
                Text(row.humidity.map { "\(Int($0.rounded()))%" } ?? "—").font(.caption.weight(.semibold))
            case "pressure":
                Text(row.pressure.map { String(format: "%.2f\"", $0 * 0.02953) } ?? "—").font(.caption.weight(.semibold))
            case "cloud":
                Text(row.cloudLow.map { "L\(Int($0.rounded()))" } ?? "L—").font(.caption2)
                Text(row.cloudMid.map { "M\(Int($0.rounded()))" } ?? "M—").font(.caption2).foregroundStyle(theme.muted)
                Text(row.cloudHigh.map { "H\(Int($0.rounded()))" } ?? "H—").font(.caption2).foregroundStyle(theme.muted)
            default:
                Text(row.temp.map { "\(Int($0.rounded()))°" } ?? "—").font(.caption.weight(.semibold))
            }
        }
        .frame(width: 56)
    }

    private var hourlyUnit: String {
        switch hourlyMode {
        case "precip": return "in"
        case "wind": return "mph"
        case "uv": return "UV"
        case "humidity": return "%"
        case "pressure": return "inHg"
        case "cloud": return "%"
        default: return "°F"
        }
    }

    private var dailyUnit: String {
        switch dailySeries {
        case "precip": return "in"
        case "uv": return "UV"
        case "wind": return "mph"
        case "cloud": return "%"
        default: return "°F"
        }
    }

    private var hourlyCloudSamples: [CloudSample] {
        model.hourlyRows.flatMap { row in
            [
                CloudSample(id: "\(row.id)-low", axis: row.time, label: row.clock, series: "Low", value: row.cloudLow ?? 0),
                CloudSample(id: "\(row.id)-mid", axis: row.time, label: row.clock, series: "Mid", value: row.cloudMid ?? 0),
                CloudSample(id: "\(row.id)-high", axis: row.time, label: row.clock, series: "High", value: row.cloudHigh ?? 0)
            ]
        }
    }

    private var dailyCloudSamples: [CloudSample] {
        model.dailyRows.flatMap { day in
            [
                CloudSample(id: "\(day.id)-low", axis: day.label, label: day.label, series: "Low", value: cloudAverage(day, "cloud_cover_low")),
                CloudSample(id: "\(day.id)-mid", axis: day.label, label: day.label, series: "Mid", value: cloudAverage(day, "cloud_cover_mid")),
                CloudSample(id: "\(day.id)-high", axis: day.label, label: day.label, series: "High", value: cloudAverage(day, "cloud_cover_high"))
            ]
        }
    }

    private func cloudAverage(_ day: DayRow, _ field: String) -> Double {
        guard let weather = model.weather else { return 0 }
        return LogicEngine.shared.number("getAverageHourlyValueForDate", [weather.hourly.raw, field, day.date]) ?? 0
    }

    private func cloudChart(samples: [CloudSample], showXAxis: Bool) -> some View {
        Chart(samples) { sample in
            LineMark(x: .value("t", sample.axis), y: .value("%", sample.value))
                .foregroundStyle(by: .value("Layer", sample.series))
                .interpolationMethod(.catmullRom)
        }
        .chartForegroundStyleScale([
            "Low": theme.cloudLow,
            "Mid": theme.cloudMid,
            "High": theme.cloudHigh
        ])
        .chartLegend(position: .bottom)
        .chartYScale(domain: 0...100)
        .chartYAxisLabel("%")
        .chartXAxis {
            if showXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(theme.grid)
                    AxisValueLabel {
                        if let raw = value.as(String.self) {
                            Text(LogicEngine.shared.string("formatIsoLocalClock", [raw]) ?? raw)
                                .foregroundStyle(theme.muted)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(theme.grid)
                AxisValueLabel().foregroundStyle(theme.muted)
            }
        }
        .frame(height: 200)
    }

    private func int(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))°"
    }
}

struct CloudSample: Identifiable {
    let id: String
    let axis: String
    let label: String
    let series: String
    let value: Double
}

private struct ForecastAxisStyle: ViewModifier {
    let theme: JWPalette
    let labeledX: Bool

    func body(content: Content) -> some View {
        content
            .chartXAxis {
                if labeledX {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(theme.grid)
                        AxisValueLabel {
                            if let raw = value.as(String.self) {
                                Text(LogicEngine.shared.string("formatIsoLocalClock", [raw]) ?? raw)
                                    .foregroundStyle(theme.muted)
                            }
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(theme.grid)
                    AxisValueLabel().foregroundStyle(theme.muted)
                }
            }
    }
}
