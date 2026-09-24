import SwiftUI
import Charts

/// Shared forecast-chart menu. Ids match the website `<select>` values
/// (`temp`, `feelslike`, `niceweather`, …). `conditions` is the old hourly default.
enum ForecastSeries: String, CaseIterable, Identifiable {
    case temp, feelslike, niceweather, precip, wind, uv, humidity, pressure, snow, cloud, brightness, tides, moon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .temp: return "Temperature"
        case .feelslike: return "Feels Like"
        case .niceweather: return "Nice Weather"
        case .precip: return "Precipitation"
        case .wind: return "Wind Speed"
        case .uv: return "UV index"
        case .humidity: return "Humidity"
        case .pressure: return "Pressure"
        case .snow: return "Snowfall"
        case .cloud: return "Cloud Cover"
        case .brightness: return "Brightness"
        case .tides: return "Tides"
        case .moon: return "Moon Phase"
        }
    }

    static func normalized(_ raw: String) -> String {
        switch raw {
        case "conditions": return temp.rawValue
        case "feelsLike": return feelslike.rawValue
        case "niceWeather": return niceweather.rawValue
        case "moonPhase": return moon.rawValue
        default: return ForecastSeries(rawValue: raw)?.rawValue ?? temp.rawValue
        }
    }

    static func options(includeTides: Bool) -> [ForecastSeries] {
        allCases.filter { includeTides || $0 != .tides }
    }
}

struct ForecastView: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var hourlyMode = ForecastSeries.normalized(LaunchArgs.hourly)
    @State private var dailySeries = ForecastSeries.normalized(LaunchArgs.daily)

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        TabScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                WeatherCard(title: "Next 48 hours") {
                    seriesMenu(selection: $hourlyMode, label: "48-hour chart")
                    chart48
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.hourlyRows) { row in
                                hourlyChip(row)
                            }
                        }
                    }
                }

                WeatherCard(title: "14-day") {
                    seriesMenu(selection: $dailySeries, label: "14-day chart")
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
            if LaunchArgs.value("hourly") != nil { hourlyMode = ForecastSeries.normalized(LaunchArgs.hourly) }
            if LaunchArgs.value("daily") != nil { dailySeries = ForecastSeries.normalized(LaunchArgs.daily) }
        }
    }

    private func seriesMenu(selection: Binding<String>, label: String) -> some View {
        let options = ForecastSeries.options(includeTides: model.tides != nil)
        let current = options.first { $0.rawValue == selection.wrappedValue } ?? .temp
        return Menu {
            Picker(label, selection: selection) {
                ForEach(options) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(current.title)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(theme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(theme.tile, in: Capsule())
            .overlay(Capsule().stroke(theme.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var chart48: some View {
        if hourlyMode == "tides", let tides = model.tides {
            tideChart(Array(tides.curve.prefix(192)))
        } else if hourlyMode == "cloud" {
            cloudChart(samples: hourlyCloudSamples, showXAxis: true)
        } else if hourlyMode == "wind" {
            windChart(model.hourlyRows.map { row in
                WindSample(id: "h\(row.id)", axis: row.time, speed: row.wind ?? 0, gust: row.windGust ?? 0)
            }, showXAxis: true)
        } else {
            singleSeriesChart(hourlyPoints, bars: hourlyMode == "precip" || hourlyMode == "snow", showXAxis: true, domain: hourlyYDomain, unit: seriesUnit(hourlyMode))
        }
    }

    @ViewBuilder
    private var dailyChart: some View {
        if dailySeries == "cloud" {
            cloudChart(samples: dailyCloudSamples, showXAxis: false)
        } else if dailySeries == "tides", let tides = model.tides {
            tideChart(tides.curve)
        } else if dailySeries == "wind" {
            windChart(model.dailyRows.map { day in
                WindSample(id: "d\(day.id)", axis: day.label, speed: day.wind ?? 0, gust: dailyGust(day))
            }, showXAxis: false)
        } else if dailySeries == "temp" || dailySeries == "feelslike" {
            rangeChart(dailyRangeSamples, showXAxis: false)
        } else {
            singleSeriesChart(dailyPoints, bars: dailySeries == "precip" || dailySeries == "snow", showXAxis: false, domain: dailyYDomain, unit: seriesUnit(dailySeries))
        }
    }

    private func tideChart(_ curve: [TideExtreme]) -> some View {
        Chart(curve) { point in
            LineMark(x: .value("t", point.time), y: .value("ft", point.value))
                .foregroundStyle(theme.accent)
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .frame(height: 150)
    }

    private func windChart(_ samples: [WindSample], showXAxis: Bool) -> some View {
        Chart(samples) { sample in
            LineMark(x: .value("t", sample.axis), y: .value("mph", sample.speed))
                .foregroundStyle(by: .value("series", "Speed"))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("t", sample.axis), y: .value("mph", sample.gust))
                .foregroundStyle(by: .value("series", "Gust"))
                .interpolationMethod(.catmullRom)
        }
        .chartForegroundStyleScale(["Speed": theme.accent, "Gust": theme.gold])
        .chartLegend(position: .bottom)
        .chartYAxisLabel("mph")
        .modifier(ForecastAxisStyle(theme: theme, labeledX: showXAxis))
        .frame(height: 200)
    }

    private func rangeChart(_ samples: [RangeSample], showXAxis: Bool) -> some View {
        Chart(samples) { sample in
            LineMark(x: .value("t", sample.axis), y: .value("°", sample.high))
                .foregroundStyle(by: .value("series", "High"))
            LineMark(x: .value("t", sample.axis), y: .value("°", sample.low))
                .foregroundStyle(by: .value("series", "Low"))
        }
        .chartForegroundStyleScale(["High": Color.orange, "Low": theme.accent])
        .chartLegend(position: .bottom)
        .chartYAxisLabel("°F")
        .modifier(ForecastAxisStyle(theme: theme, labeledX: showXAxis))
        .frame(height: 180)
    }

    @ViewBuilder
    private func singleSeriesChart(_ samples: [PlotPoint], bars: Bool, showXAxis: Bool, domain: ClosedRange<Double>?, unit: String) -> some View {
        let plotted = seriesMarks(samples, bars: bars, showXAxis: showXAxis, unit: unit)
        if let domain {
            plotted.chartYScale(domain: domain)
        } else {
            plotted
        }
    }

    private func seriesMarks(_ samples: [PlotPoint], bars: Bool, showXAxis: Bool, unit: String) -> some View {
        Chart(samples) { sample in
            if bars {
                BarMark(x: .value("t", sample.axis), y: .value("v", sample.value))
                    .foregroundStyle(theme.accent)
            } else {
                LineMark(x: .value("t", sample.axis), y: .value("v", sample.value))
                    .foregroundStyle(theme.accent)
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartYAxisLabel(unit)
        .modifier(ForecastAxisStyle(theme: theme, labeledX: showXAxis))
        .frame(height: 180)
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
            case "feelslike":
                Text(row.feels.map { "\(Int($0.rounded()))°" } ?? "—").font(.caption.weight(.semibold))
            case "snow":
                Text(row.snow.map { String(format: "%.2f\"", $0) } ?? "0\"").font(.caption.weight(.semibold))
            case "brightness":
                Text("\(Int(hourlyBrightness(row).rounded()))%").font(.caption.weight(.semibold))
            case "niceweather":
                Text(String(format: "%.0f", niceScore(forHour: row.time))).font(.caption.weight(.semibold))
            case "moon":
                Text(String(format: "%.0f%%", moonPhase(row.time) * 100)).font(.caption.weight(.semibold))
            default:
                Text(row.temp.map { "\(Int($0.rounded()))°" } ?? "—").font(.caption.weight(.semibold))
            }
        }
        .frame(width: 56)
    }

    private func seriesUnit(_ series: String) -> String {
        switch series {
        case "precip", "snow": return "in"
        case "wind": return "mph"
        case "uv": return "UV"
        case "humidity", "cloud", "brightness": return "%"
        case "pressure": return "inHg"
        case "niceweather": return "/10"
        case "tides": return "ft"
        case "moon": return "phase"
        default: return "°F"
        }
    }

    private var hourlyPoints: [PlotPoint] {
        model.hourlyRows.map { row in
            PlotPoint(id: "h\(row.id)", axis: row.time, value: hourlyValue(row))
        }
    }

    private var dailyPoints: [PlotPoint] {
        model.dailyRows.map { day in
            PlotPoint(id: "d\(day.id)", axis: day.label, value: dailyValue(day))
        }
    }

    private var dailyRangeSamples: [RangeSample] {
        let feels = dailySeries == "feelslike"
        return model.dailyRows.map { day in
            RangeSample(
                id: "r\(day.id)",
                axis: day.label,
                high: (feels ? day.feelsHigh : day.high) ?? 0,
                low: (feels ? day.feelsLow : day.low) ?? 0
            )
        }
    }

    private func hourlyValue(_ row: HourRow) -> Double {
        switch hourlyMode {
        case "feelslike": return row.feels ?? 0
        case "precip": return row.precip ?? 0
        case "snow": return row.snow ?? 0
        case "uv": return row.uv ?? 0
        case "humidity": return row.humidity ?? 0
        case "pressure": return (row.pressure ?? 0) * 0.02953
        case "niceweather": return niceScore(forHour: row.time)
        case "brightness": return hourlyBrightness(row)
        case "moon": return moonPhase(row.time)
        default: return row.temp ?? 0
        }
    }

    private func dailyValue(_ day: DayRow) -> Double {
        switch dailySeries {
        case "precip": return day.precip ?? 0
        case "snow": return dailySnow(day)
        case "uv": return day.uv ?? 0
        case "humidity": return dailyAverage("relative_humidity_2m", day.date)
        case "pressure": return noonPressureInHg(day.date)
        case "niceweather": return niceScore(forDate: day.date, index: day.id)
        case "brightness": return dailyBrightness(day.date)
        case "moon": return moonPhase(day.date + "T12:00")
        default: return day.high ?? 0
        }
    }

    private var hourlyYDomain: ClosedRange<Double>? {
        switch hourlyMode {
        case "humidity", "brightness": return 0...100
        case "niceweather": return 0...10
        case "uv": return 0...max(1, model.hourlyRows.map { $0.uv ?? 0 }.max() ?? 1)
        default: return nil
        }
    }

    private var dailyYDomain: ClosedRange<Double>? {
        switch dailySeries {
        case "humidity", "brightness": return 0...100
        case "niceweather": return 0...10
        case "moon": return 0...1
        case "uv": return 0...max(1, model.dailyRows.map { $0.uv ?? 0 }.max() ?? 1)
        default: return nil
        }
    }

    private var maxHourlyRadiation: Double {
        max(model.hourlyRows.map { $0.radiation ?? 0 }.max() ?? 0, 1)
    }

    private var maxDailyRadiation: Double {
        let peak = model.dailyRows.map { dailyAverage("shortwave_radiation", $0.date) }.max() ?? 0
        return max(peak, 1)
    }

    private func hourlyBrightness(_ row: HourRow) -> Double {
        ((row.radiation ?? 0) / maxHourlyRadiation) * 100
    }

    private func dailyBrightness(_ date: String) -> Double {
        (dailyAverage("shortwave_radiation", date) / maxDailyRadiation) * 100
    }

    private func dailyAverage(_ field: String, _ date: String) -> Double {
        guard let weather = model.weather else { return 0 }
        return LogicEngine.shared.number("getAverageHourlyValueForDate", [weather.hourly.raw, field, date]) ?? 0
    }

    private func noonPressureInHg(_ date: String) -> Double {
        guard let weather = model.weather else { return 0 }
        let times = weather.hourly.strings("time")
        let pressures = weather.hourly.numbers("surface_pressure")
        let noon = times.firstIndex { $0.hasPrefix(date) && $0.contains("T12:") } ?? times.firstIndex { $0.hasPrefix(date) }
        guard let noon, noon < pressures.count, let hpa = pressures[noon] else { return 0 }
        return hpa * 0.02953
    }

    private func dailySnow(_ day: DayRow) -> Double {
        guard let weather = model.weather else { return 0 }
        let values = weather.daily.numbers("snowfall_sum")
        guard day.id < values.count, let snow = values[day.id] else { return 0 }
        return snow
    }

    private func dailyGust(_ day: DayRow) -> Double {
        guard let weather = model.weather else { return 0 }
        let values = weather.daily.numbers("wind_gusts_10m_max")
        guard day.id < values.count, let gust = values[day.id] else { return 0 }
        return gust
    }

    private func niceScore(forDate date: String, index: Int) -> Double {
        guard let weather = model.weather else { return 0 }
        let avg = LogicEngine.shared.object("calculateDailyAveragesForDateString", [weather.hourly.raw, date]) as Any
        let breakdown = LogicEngine.shared.object("getNiceWeatherBreakdown", [weather.root.raw, avg, index])
        return JSONMap(breakdown).number("score") ?? 0
    }

    private func niceScore(forHour iso: String) -> Double {
        let date = String(iso.prefix(10))
        guard let day = model.dailyRows.first(where: { $0.date == date }) else { return 0 }
        return niceScore(forDate: date, index: day.id)
    }

    private func moonPhase(_ iso: String) -> Double {
        let ms = LogicEngine.shared.number("parseLocationLocalIso", [iso, model.weather?.utcOffset ?? 0]) ?? 0
        return LogicEngine.shared.number("calculateMoonPhase", [ms]) ?? 0
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

struct PlotPoint: Identifiable {
    let id: String
    let axis: String
    let value: Double
}

struct WindSample: Identifiable {
    let id: String
    let axis: String
    let speed: Double
    let gust: Double
}

struct RangeSample: Identifiable {
    let id: String
    let axis: String
    let high: Double
    let low: Double
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
