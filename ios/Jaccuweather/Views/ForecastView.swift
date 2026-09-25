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
    @State private var hourlySelection: Date?
    @State private var dailySelection: Date?
    @State private var hourlyTideSelection: Date?
    @State private var dailyTideSelection: Date?

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        TabScreenScroll {
            WeatherCard(title: "Next 48 hours") {
                seriesMenu(selection: $hourlyMode, label: "48-hour chart")
                chart48
                HourlyStrip(rows: model.hourlyRows, mode: hourlyMode, theme: theme)
                    .equatable()
            }

            WeatherCard(title: "14-day") {
                seriesMenu(selection: $dailySeries, label: "14-day chart")
                dailyChart
                DailyDetailList(days: model.dailyRows, theme: theme)
                    .equatable()
            }
        }
        .navigationTitle("Forecast")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if LaunchArgs.value("hourly") != nil { hourlyMode = ForecastSeries.normalized(LaunchArgs.hourly) }
            if LaunchArgs.value("daily") != nil { dailySeries = ForecastSeries.normalized(LaunchArgs.daily) }
        }
        .onChange(of: hourlyMode) { _, _ in
            hourlySelection = nil
            hourlyTideSelection = nil
        }
        .onChange(of: dailySeries) { _, _ in
            dailySelection = nil
            dailyTideSelection = nil
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
            let curve = Array(tides.curve.prefix(192))
            scrubBanner(tideReadout(hourlyTideSelection, curve: curve))
            tideChart(curve, selection: $hourlyTideSelection, hourly: true)
                .accessibilityIdentifier("hourly-chart")
        } else if hourlyMode == "cloud" {
            scrubBanner(hourlyScrubText)
            cloudChart(samples: hourlyCloudSamples, hourly: true, selection: $hourlySelection)
                .accessibilityIdentifier("hourly-chart")
        } else if hourlyMode == "wind" {
            scrubBanner(hourlyScrubText)
            windChart(model.hourlyRows.map { row in
                WindSample(id: "h\(row.id)", axis: ForecastDates.hour(row.time), speed: row.wind ?? 0, gust: row.windGust ?? 0)
            }, hourly: true, selection: $hourlySelection)
                .accessibilityIdentifier("hourly-chart")
        } else {
            scrubBanner(hourlyScrubText)
            singleSeriesChart(
                hourlyPoints,
                bars: hourlyMode == "precip" || hourlyMode == "snow",
                hourly: true,
                domain: hourlyYDomain,
                unit: seriesUnit(hourlyMode),
                selection: $hourlySelection
            )
            .accessibilityIdentifier("hourly-chart")
        }
    }

    @ViewBuilder
    private var dailyChart: some View {
        if dailySeries == "cloud" {
            scrubBanner(dailyScrubText)
            cloudChart(samples: dailyCloudSamples, hourly: false, selection: $dailySelection)
                .accessibilityIdentifier("daily-chart")
        } else if dailySeries == "tides", let tides = model.tides {
            scrubBanner(tideReadout(dailyTideSelection, curve: tides.curve))
            tideChart(tides.curve, selection: $dailyTideSelection, hourly: false)
                .accessibilityIdentifier("daily-chart")
        } else if dailySeries == "wind" {
            scrubBanner(dailyScrubText)
            windChart(model.dailyRows.map { day in
                WindSample(id: "d\(day.id)", axis: ForecastDates.day(day.date), speed: day.wind ?? 0, gust: day.gust)
            }, hourly: false, selection: $dailySelection)
                .accessibilityIdentifier("daily-chart")
        } else if dailySeries == "temp" || dailySeries == "feelslike" {
            scrubBanner(dailyScrubText)
            rangeChart(dailyRangeSamples, hourly: false, selection: $dailySelection)
                .accessibilityIdentifier("daily-chart")
        } else {
            scrubBanner(dailyScrubText)
            singleSeriesChart(
                dailyPoints,
                bars: dailySeries == "precip" || dailySeries == "snow",
                hourly: false,
                domain: dailyYDomain,
                unit: seriesUnit(dailySeries),
                selection: $dailySelection
            )
            .accessibilityIdentifier("daily-chart")
        }
    }

    @ViewBuilder
    private func scrubBanner(_ text: String?) -> some View {
        if let text {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(theme.tile, in: Capsule())
                .overlay(Capsule().stroke(theme.accent.opacity(0.55), lineWidth: 1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func tideChart(_ curve: [TideExtreme], selection: Binding<Date?>, hourly: Bool) -> some View {
        let nearest = selection.wrappedValue.flatMap { nearestTide($0, in: curve) }
        return Chart {
            ForEach(curve) { point in
                LineMark(x: .value("t", point.time), y: .value("ft", point.value))
                    .foregroundStyle(theme.accent)
                    .interpolationMethod(.catmullRom)
            }
            if let nearest {
                RuleMark(x: .value("t", nearest.time))
                    .foregroundStyle(theme.accent.opacity(0.9))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(x: .value("t", nearest.time), y: .value("ft", nearest.value))
                    .foregroundStyle(theme.gold)
                    .symbolSize(70)
            }
        }
        .chartYAxisLabel("ft")
        .chartXAxis {
            AxisMarks(values: .stride(by: hourly ? .hour : .day, count: hourly ? 6 : 2)) { _ in
                AxisGridLine().foregroundStyle(theme.grid)
                AxisValueLabel(format: hourly ? .dateTime.hour() : .dateTime.weekday(.abbreviated).day(), centered: true)
                    .foregroundStyle(theme.muted)
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(theme.grid)
                AxisValueLabel().foregroundStyle(theme.muted)
            }
        }
        .modifier(DateScrubber(selection: selection))
        .frame(height: 200)
    }

    private func windChart(_ samples: [WindSample], hourly: Bool, selection: Binding<Date?>) -> some View {
        let axes = ForecastDates.unique(samples.map(\.axis))
        let selected = selection.wrappedValue.flatMap { axis in samples.first { $0.axis == axis } }
        return Chart {
            ForEach(samples) { sample in
                LineMark(x: .value("t", sample.axis), y: .value("mph", sample.speed))
                    .foregroundStyle(by: .value("series", "Speed"))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("t", sample.axis), y: .value("mph", sample.gust))
                    .foregroundStyle(by: .value("series", "Gust"))
                    .interpolationMethod(.catmullRom)
            }
            if let selected {
                RuleMark(x: .value("t", selected.axis))
                    .foregroundStyle(theme.text.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(x: .value("t", selected.axis), y: .value("mph", selected.speed))
                    .foregroundStyle(theme.gold)
                    .symbolSize(70)
                PointMark(x: .value("t", selected.axis), y: .value("mph", selected.gust))
                    .foregroundStyle(theme.gold)
                    .symbolSize(70)
            }
        }
        .chartForegroundStyleScale(["Speed": theme.accent, "Gust": theme.gold])
        .chartLegend(position: .bottom)
        .chartYAxisLabel("mph")
        .modifier(ForecastAxisStyle(theme: theme, hourly: hourly))
        .modifier(SeriesScrubber(dates: axes, selection: selection))
        .frame(height: 220)
    }

    private func rangeChart(_ samples: [RangeSample], hourly: Bool, selection: Binding<Date?>) -> some View {
        let axes = ForecastDates.unique(samples.map(\.axis))
        let selected = selection.wrappedValue.flatMap { axis in samples.first { $0.axis == axis } }
        return Chart {
            ForEach(samples) { sample in
                LineMark(x: .value("t", sample.axis), y: .value("°", sample.high))
                    .foregroundStyle(by: .value("series", "High"))
                LineMark(x: .value("t", sample.axis), y: .value("°", sample.low))
                    .foregroundStyle(by: .value("series", "Low"))
            }
            if let selected {
                RuleMark(x: .value("t", selected.axis))
                    .foregroundStyle(theme.text.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(x: .value("t", selected.axis), y: .value("°", selected.high))
                    .foregroundStyle(theme.gold)
                    .symbolSize(70)
                PointMark(x: .value("t", selected.axis), y: .value("°", selected.low))
                    .foregroundStyle(theme.gold)
                    .symbolSize(70)
            }
        }
        .chartForegroundStyleScale(["High": Color.orange, "Low": theme.accent])
        .chartLegend(position: .bottom)
        .chartYAxisLabel("°F")
        .modifier(ForecastAxisStyle(theme: theme, hourly: hourly))
        .modifier(SeriesScrubber(dates: axes, selection: selection))
        .frame(height: 220)
    }

    @ViewBuilder
    private func singleSeriesChart(_ samples: [PlotPoint], bars: Bool, hourly: Bool, domain: ClosedRange<Double>?, unit: String, selection: Binding<Date?>) -> some View {
        let plotted = seriesMarks(samples, bars: bars, hourly: hourly, unit: unit, selection: selection)
        if let domain {
            plotted.chartYScale(domain: domain)
        } else {
            plotted
        }
    }

    private func seriesMarks(_ samples: [PlotPoint], bars: Bool, hourly: Bool, unit: String, selection: Binding<Date?>) -> some View {
        let axes = ForecastDates.unique(samples.map(\.axis))
        let selected = selection.wrappedValue.flatMap { axis in samples.first { $0.axis == axis } }
        return Chart {
            ForEach(samples) { sample in
                if bars {
                    BarMark(x: .value("t", sample.axis), y: .value("v", sample.value))
                        .foregroundStyle(theme.accent)
                } else {
                    LineMark(x: .value("t", sample.axis), y: .value("v", sample.value))
                        .foregroundStyle(theme.accent)
                        .interpolationMethod(.catmullRom)
                }
            }
            if let selected {
                RuleMark(x: .value("t", selected.axis))
                    .foregroundStyle(theme.text.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(x: .value("t", selected.axis), y: .value("v", selected.value))
                    .foregroundStyle(theme.gold)
                    .symbolSize(80)
            }
        }
        .chartYAxisLabel(unit)
        .modifier(ForecastAxisStyle(theme: theme, hourly: hourly))
        .modifier(SeriesScrubber(dates: axes, selection: selection))
        .frame(height: 220)
    }

    private var hourlyScrubText: String? {
        guard let axis = hourlySelection, let row = model.hourlyRows.first(where: { ForecastDates.sameHour($0.time, axis) }) else { return nil }
        let when = row.clock
        switch hourlyMode {
        case "feelslike":
            return "\(when)  \(row.feels.map { "\(Int($0.rounded()))°" } ?? "—")"
        case "precip":
            let amount = row.precip.map { String(format: "%.2f in", $0) } ?? "0 in"
            let chance = row.precipChance.map { " · \($0)%" } ?? ""
            return "\(when)  \(amount)\(chance)"
        case "wind":
            let speed = row.wind.map { String(format: "%.0f mph", $0) } ?? "—"
            let dir = row.windDir.map { " \(WindCompass.label($0))" } ?? ""
            let gust = row.windGust.map { String(format: " · gust %.0f", $0) } ?? ""
            return "\(when)  \(speed)\(dir)\(gust)"
        case "uv":
            return "\(when)  \(row.uv.map { String(format: "UV %.0f", $0) } ?? "—")"
        case "humidity":
            return "\(when)  \(row.humidity.map { "\(Int($0.rounded()))%" } ?? "—")"
        case "pressure":
            return "\(when)  \(row.pressure.map { String(format: "%.2f inHg", $0 * 0.02953) } ?? "—")"
        case "snow":
            return "\(when)  \(row.snow.map { String(format: "%.2f in", $0) } ?? "0 in")"
        case "cloud":
            let low = row.cloudLow.map { "L \(Int($0.rounded()))%" } ?? "L —"
            let mid = row.cloudMid.map { "M \(Int($0.rounded()))%" } ?? "M —"
            let high = row.cloudHigh.map { "H \(Int($0.rounded()))%" } ?? "H —"
            return "\(when)  \(low)  \(mid)  \(high)"
        case "brightness":
            return "\(when)  \(Int(row.brightness.rounded()))%"
        case "niceweather":
            return "\(when)  \(String(format: "%.0f / 10", row.niceScore))"
        case "moon":
            return "\(when)  \(String(format: "%.0f%%", row.moonPhase * 100))"
        default:
            return "\(when)  \(row.temp.map { "\(Int($0.rounded()))°" } ?? "—")"
        }
    }

    private var dailyScrubText: String? {
        guard let axis = dailySelection, let day = model.dailyRows.first(where: { ForecastDates.sameDay($0.date, axis) }) else { return nil }
        switch dailySeries {
        case "temp":
            return "\(day.label)  H \(int(day.high))  L \(int(day.low))"
        case "feelslike":
            return "\(day.label)  H \(int(day.feelsHigh))  L \(int(day.feelsLow))"
        case "precip":
            let amount = day.precip.map { String(format: "%.2f in", $0) } ?? "0 in"
            let chance = day.precipChance.map { " · \($0)%" } ?? ""
            return "\(day.label)  \(amount)\(chance)"
        case "wind":
            let speed = day.wind.map { String(format: "%.0f mph", $0) } ?? "—"
            let gust = String(format: " · gust %.0f", day.gust)
            return "\(day.label)  \(speed)\(gust)"
        case "uv":
            return "\(day.label)  \(day.uv.map { String(format: "UV %.0f", $0) } ?? "—")"
        case "humidity":
            return "\(day.label)  \(Int(day.humidityAvg.rounded()))%"
        case "pressure":
            return "\(day.label)  \(String(format: "%.2f inHg", day.pressureInHg))"
        case "snow":
            return "\(day.label)  \(String(format: "%.2f in", day.snowSum))"
        case "cloud":
            let low = Int(day.cloudLowAvg.rounded())
            let mid = Int(day.cloudMidAvg.rounded())
            let high = Int(day.cloudHighAvg.rounded())
            return "\(day.label)  L \(low)%  M \(mid)%  H \(high)%"
        case "brightness":
            return "\(day.label)  \(Int(day.brightness.rounded()))%"
        case "niceweather":
            return "\(day.label)  \(String(format: "%.0f / 10", day.niceScore))"
        case "moon":
            return "\(day.label)  \(String(format: "%.0f%%", day.moonPhase * 100))"
        default:
            return "\(day.label)  \(int(day.high))"
        }
    }

    private func tideReadout(_ date: Date?, curve: [TideExtreme]) -> String? {
        guard let date, let point = nearestTide(date, in: curve) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE h:mm a"
        return "\(formatter.string(from: point.time))  \(String(format: "%.1f ft", point.value))"
    }

    private func nearestTide(_ date: Date, in curve: [TideExtreme]) -> TideExtreme? {
        curve.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
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
            PlotPoint(id: "h\(row.id)", axis: ForecastDates.hour(row.time), value: hourlyValue(row))
        }
    }

    private var dailyPoints: [PlotPoint] {
        model.dailyRows.map { day in
            PlotPoint(id: "d\(day.id)", axis: ForecastDates.day(day.date), value: dailyValue(day))
        }
    }

    private var dailyRangeSamples: [RangeSample] {
        let feels = dailySeries == "feelslike"
        return model.dailyRows.map { day in
            RangeSample(
                id: "r\(day.id)",
                axis: ForecastDates.day(day.date),
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
        case "niceweather": return row.niceScore
        case "brightness": return row.brightness
        case "moon": return row.moonPhase
        default: return row.temp ?? 0
        }
    }

    private func dailyValue(_ day: DayRow) -> Double {
        switch dailySeries {
        case "precip": return day.precip ?? 0
        case "snow": return day.snowSum
        case "uv": return day.uv ?? 0
        case "humidity": return day.humidityAvg
        case "pressure": return day.pressureInHg
        case "niceweather": return day.niceScore
        case "brightness": return day.brightness
        case "moon": return day.moonPhase
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

    private var hourlyCloudSamples: [CloudSample] {
        model.hourlyRows.flatMap { row in
            [
                CloudSample(id: "\(row.id)-low", axis: ForecastDates.hour(row.time), label: row.clock, series: "Low", value: row.cloudLow ?? 0),
                CloudSample(id: "\(row.id)-mid", axis: ForecastDates.hour(row.time), label: row.clock, series: "Mid", value: row.cloudMid ?? 0),
                CloudSample(id: "\(row.id)-high", axis: ForecastDates.hour(row.time), label: row.clock, series: "High", value: row.cloudHigh ?? 0)
            ]
        }
    }

    private var dailyCloudSamples: [CloudSample] {
        model.dailyRows.flatMap { day in
            [
                CloudSample(id: "\(day.id)-low", axis: ForecastDates.day(day.date), label: day.label, series: "Low", value: day.cloudLowAvg),
                CloudSample(id: "\(day.id)-mid", axis: ForecastDates.day(day.date), label: day.label, series: "Mid", value: day.cloudMidAvg),
                CloudSample(id: "\(day.id)-high", axis: ForecastDates.day(day.date), label: day.label, series: "High", value: day.cloudHighAvg)
            ]
        }
    }

    private func cloudChart(samples: [CloudSample], hourly: Bool, selection: Binding<Date?>) -> some View {
        let axes = ForecastDates.unique(samples.map(\.axis))
        let selectedAxis = selection.wrappedValue
        let selected = samples.filter { $0.axis == selectedAxis }
        return Chart {
            ForEach(samples) { sample in
                LineMark(x: .value("t", sample.axis), y: .value("%", sample.value))
                    .foregroundStyle(by: .value("Layer", sample.series))
                    .interpolationMethod(.catmullRom)
            }
            if let selectedAxis, !selected.isEmpty {
                RuleMark(x: .value("t", selectedAxis))
                    .foregroundStyle(theme.text.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                ForEach(selected) { sample in
                    PointMark(x: .value("t", sample.axis), y: .value("%", sample.value))
                        .foregroundStyle(theme.gold)
                        .symbolSize(56)
                }
            }
        }
        .chartForegroundStyleScale([
            "Low": theme.cloudLow,
            "Mid": theme.cloudMid,
            "High": theme.cloudHigh
        ])
        .chartLegend(position: .bottom)
        .chartYScale(domain: 0...100)
        .chartYAxisLabel("%")
        .modifier(ForecastAxisStyle(theme: theme, hourly: hourly))
        .modifier(SeriesScrubber(dates: axes, selection: selection))
        .frame(height: 220)
    }

    private func int(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))°"
    }
}

/// Hour and day lists ignore chart scrubbing so icon rows are not rebuilt on each drag point.
private struct HourlyStrip: View, Equatable {
    let rows: [HourRow]
    let mode: String
    let theme: JWPalette

    static func == (lhs: HourlyStrip, rhs: HourlyStrip) -> Bool {
        lhs.mode == rhs.mode && lhs.rows == rhs.rows
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(rows) { row in
                    chip(row)
                }
            }
        }
    }

    private func chip(_ row: HourRow) -> some View {
        VStack(spacing: 6) {
            Text(row.clock).font(.caption2).foregroundStyle(theme.muted)
            if mode != "wind" {
                SVGIconView(fileName: row.iconFile, folder: "weather", pointSize: 28).frame(width: 28, height: 28)
            }
            switch mode {
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
                Text(row.uvLabel).font(.caption2).foregroundStyle(theme.muted)
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
                Text("\(Int(row.brightness.rounded()))%").font(.caption.weight(.semibold))
            case "niceweather":
                Text(String(format: "%.0f", row.niceScore)).font(.caption.weight(.semibold))
            case "moon":
                Text(String(format: "%.0f%%", row.moonPhase * 100)).font(.caption.weight(.semibold))
            default:
                Text(row.temp.map { "\(Int($0.rounded()))°" } ?? "—").font(.caption.weight(.semibold))
            }
        }
        .frame(width: 56)
    }
}

private struct DailyDetailList: View, Equatable {
    let days: [DayRow]
    let theme: JWPalette

    static func == (lhs: DailyDetailList, rhs: DailyDetailList) -> Bool {
        lhs.days == rhs.days
    }

    var body: some View {
        ForEach(days) { day in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    Text(day.fullLabel)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .layoutPriority(1)
                        .accessibilityIdentifier("forecast-day-header")
                    SVGIconView(fileName: day.iconFile, folder: "weather", pointSize: 28)
                        .frame(width: 28, height: 28)
                    Spacer(minLength: 6)
                    Text(day.precipChance.map { "\($0)%" } ?? "")
                        .font(.caption).foregroundStyle(theme.muted)
                        .lineLimit(1)
                    Text(day.uv.map { String(format: "UV %.0f", $0) } ?? "")
                        .font(.caption).foregroundStyle(theme.muted)
                        .lineLimit(1)
                    Text(temp(day.low)).foregroundStyle(theme.muted)
                        .lineLimit(1)
                        .frame(width: 36, alignment: .trailing)
                    Text(temp(day.high)).fontWeight(.semibold)
                        .lineLimit(1)
                        .frame(width: 40, alignment: .trailing)
                }
                HStack {
                    Text(day.summary)
                    if let feels = day.feelsHigh {
                        Text("Feels \(Int(feels.rounded()))°")
                    }
                    if !day.sunriseClock.isEmpty {
                        Text(day.sunriseClock)
                    }
                }
                .font(.caption2)
                .foregroundStyle(theme.muted)
            }
            .padding(.vertical, 4)
        }
    }

    private func temp(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))°"
    }
}

struct PlotPoint: Identifiable {
    let id: String
    let axis: Date
    let value: Double
}

struct WindSample: Identifiable {
    let id: String
    let axis: Date
    let speed: Double
    let gust: Double
}

struct RangeSample: Identifiable {
    let id: String
    let axis: Date
    let high: Double
    let low: Double
}

struct CloudSample: Identifiable {
    let id: String
    let axis: Date
    let label: String
    let series: String
    let value: Double
}

private enum ForecastDates {
    private static let utc = TimeZone(secondsFromGMT: 0) ?? .gmt
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    private static let hourParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()

    private static let dayParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func hour(_ iso: String) -> Date {
        hourParser.date(from: String(iso.prefix(16))) ?? .distantPast
    }

    static func day(_ ymd: String) -> Date {
        dayParser.date(from: String(ymd.prefix(10))) ?? .distantPast
    }

    static func sameHour(_ iso: String, _ date: Date) -> Bool {
        abs(hour(iso).timeIntervalSince(date)) < 60
    }

    static func sameDay(_ ymd: String, _ date: Date) -> Bool {
        abs(day(ymd).timeIntervalSince(date)) < 12 * 3600
    }

    static func unique(_ dates: [Date]) -> [Date] {
        var seen = Set<TimeInterval>()
        return dates.filter { seen.insert($0.timeIntervalSince1970).inserted }
    }

    static func axisLabel(_ date: Date, hourly: Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        if hourly {
            let hour = calendar.component(.hour, from: date)
            let h12 = hour % 12 == 0 ? 12 : hour % 12
            let clock = "\(h12) \(hour >= 12 ? "PM" : "AM")"
            if hour == 0 {
                return "\(clock)\n\(weekday.string(from: date))"
            }
            return clock
        }
        return "\(weekday.string(from: date))\n\(calendar.component(.day, from: date))"
    }

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = utc
        formatter.dateFormat = "EEE"
        return formatter
    }()
}

private struct ForecastAxisStyle: ViewModifier {
    let theme: JWPalette
    let hourly: Bool

    func body(content: Content) -> some View {
        content
            .chartXAxis {
                AxisMarks(values: .stride(by: hourly ? .hour : .day, count: hourly ? 6 : 2, calendar: ForecastDates.calendar)) { value in
                    AxisGridLine().foregroundStyle(theme.grid)
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) {
                            Text(ForecastDates.axisLabel(date, hourly: hourly))
                                .font(.system(size: 11, weight: .semibold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(theme.text.opacity(0.92))
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

private struct SeriesScrubber: ViewModifier {
    let dates: [Date]
    @Binding var selection: Date?

    func body(content: Content) -> some View {
        content.chartOverlay { proxy in
            GeometryReader { geo in
                ChartScrubSurface { x in
                    guard !dates.isEmpty else { return }
                    let frame = proxy.plotFrame.map { geo[$0] } ?? geo.frame(in: .local)
                    guard frame.width > 0 else { return }
                    let localX = x - frame.minX
                    if let date: Date = proxy.value(atX: localX) {
                        let nearest = dates.min {
                            abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date))
                        }
                        if selection != nearest { selection = nearest }
                    } else {
                        let ratio = min(max(localX / frame.width, 0), 1)
                        let index = min(max(Int((ratio * CGFloat(dates.count - 1)).rounded()), 0), dates.count - 1)
                        let nearest = dates[index]
                        if selection != nearest { selection = nearest }
                    }
                }
            }
        }
    }
}

private struct DateScrubber: ViewModifier {
    @Binding var selection: Date?

    func body(content: Content) -> some View {
        content.chartOverlay { proxy in
            GeometryReader { geo in
                ChartScrubSurface { x in
                    guard let plot = proxy.plotFrame else { return }
                    let frame = geo[plot]
                    let localX = x - frame.minX
                    if let date: Date = proxy.value(atX: localX) {
                        selection = date
                    }
                }
            }
        }
    }
}

/// Horizontal chart scrub that leaves vertical drags to the scroll view, so pull-to-refresh still works.
private struct ChartScrubSurface: UIViewRepresentable {
    var onX: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.001)
        let pan = VerticalDeferringPan()
        let coordinator = context.coordinator
        pan.onX = { [weak pan, weak view] in
            guard let pan, let view else { return }
            coordinator.onX?(pan.location(in: view).x)
        }
        pan.delegate = pan
        view.addGestureRecognizer(pan)
        context.coordinator.pan = pan
        context.coordinator.onX = onX
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onX = onX
    }

    final class Coordinator {
        var onX: ((CGFloat) -> Void)?
        weak var pan: VerticalDeferringPan?
    }
}

private final class VerticalDeferringPan: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
    var onX: (() -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        addTarget(self, action: #selector(handle))
    }

    convenience init() { self.init(target: nil, action: nil) }

    @objc private func handle() {
        guard state == .began || state == .changed else { return }
        onX?()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let velocity = velocity(in: view)
        return abs(velocity.x) >= abs(velocity.y)
    }
}
