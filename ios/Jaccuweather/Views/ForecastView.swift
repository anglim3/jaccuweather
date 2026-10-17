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
        TabScreenScroll(scrollTo: LaunchArgs.anchor) {
            ForecastPanel(title: "48-Hour Forecast") {
                seriesMenu(selection: $hourlyMode, label: "48-hour chart")
            } content: {
                if model.hourlyRows.isEmpty {
                    if let status = forecastStatus {
                        emptyLine(status)
                    }
                } else {
                    chart48
                    HourlyStrip(rows: model.hourlyRows, mode: hourlyMode, theme: theme)
                        .equatable()
                }
            }
            .id("hourly")

            ForecastPanel(title: "14-Day Forecast") {
                seriesMenu(selection: $dailySeries, label: "14-day chart")
            } content: {
                if model.dailyRows.isEmpty {
                    if model.hourlyRows.isEmpty == false {
                        emptyLine("Daily forecast will appear here.")
                    }
                } else {
                    dailyChart
                    DailyDetailList(days: model.dailyRows, theme: theme)
                        .equatable()
                }
            }
            .id("daily")
        }
        .navigationTitle("Forecast")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("forecast-screen")
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
            HStack(spacing: 6) {
                Text(current.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.muted)
            }
            .foregroundStyle(theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.tile, in: RoundedRectangle(cornerRadius: JWMetrics.radiusChip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: JWMetrics.radiusChip, style: .continuous)
                    .stroke(theme.cardStroke, lineWidth: 1)
            )
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
                series: hourlyMode,
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
                series: dailySeries,
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
                .background(theme.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.chipStroke, lineWidth: 1)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func tideChart(_ curve: [TideExtreme], selection: Binding<Date?>, hourly: Bool) -> some View {
        let nearest = selection.wrappedValue.flatMap { nearestTide($0, in: curve) }
        let values = curve.map(\.value)
        let span = chartDomain(values, includeZero: false)
        return Chart {
            ForEach(curve) { point in
                AreaMark(
                    x: .value("t", point.time),
                    yStart: .value("base", span.lowerBound),
                    yEnd: .value("ft", point.value)
                )
                .foregroundStyle(JWChart.area(JWChart.tide))
                .interpolationMethod(.monotone)
                LineMark(x: .value("t", point.time), y: .value("ft", point.value))
                    .foregroundStyle(JWChart.tide)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if let nearest {
                RuleMark(x: .value("t", nearest.time))
                    .foregroundStyle(theme.text.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(x: .value("t", nearest.time), y: .value("ft", nearest.value))
                    .foregroundStyle(theme.gold)
                    .symbolSize(70)
            }
        }
        .chartYScale(domain: span)
        .chartYAxisLabel("ft")
        .modifier(ForecastAxisStyle(theme: theme, hourly: hourly))
        .modifier(DateScrubber(selection: selection))
        .frame(height: 236)
    }

    private func windChart(_ samples: [WindSample], hourly: Bool, selection: Binding<Date?>) -> some View {
        let axes = ForecastDates.unique(samples.map(\.axis))
        let selected = selection.wrappedValue.flatMap { axis in samples.first { $0.axis == axis } }
        let span = chartDomain(samples.flatMap { [$0.speed, $0.gust] }, includeZero: true)
        return Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("t", sample.axis),
                    yStart: .value("base", span.lowerBound),
                    yEnd: .value("mph", sample.speed)
                )
                .foregroundStyle(JWChart.area(JWChart.wind))
                .interpolationMethod(.monotone)
                LineMark(x: .value("t", sample.axis), y: .value("mph", sample.speed))
                    .foregroundStyle(by: .value("series", "Speed"))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                LineMark(x: .value("t", sample.axis), y: .value("mph", sample.gust))
                    .foregroundStyle(by: .value("series", "Gust"))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
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
        .chartYScale(domain: span)
        .chartForegroundStyleScale(["Speed": JWChart.wind, "Gust": JWChart.orange])
        .chartLegend(position: .top, alignment: .leading, spacing: 8)
        .chartYAxisLabel("mph")
        .modifier(ForecastAxisStyle(theme: theme, hourly: hourly))
        .modifier(SeriesScrubber(dates: axes, selection: selection))
        .frame(height: 248)
    }

    private func rangeChart(_ samples: [RangeSample], hourly: Bool, selection: Binding<Date?>) -> some View {
        let axes = ForecastDates.unique(samples.map(\.axis))
        let selected = selection.wrappedValue.flatMap { axis in samples.first { $0.axis == axis } }
        let series = hourly ? hourlyMode : dailySeries
        let highColor = JWChart.high(series)
        let lowColor = JWChart.low(series)
        let span = chartDomain(samples.flatMap { [$0.high, $0.low] }, includeZero: false)
        return Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("t", sample.axis),
                    yStart: .value("base", span.lowerBound),
                    yEnd: .value("high", sample.high)
                )
                .foregroundStyle(by: .value("band", "HighFill"))
                .interpolationMethod(.monotone)
            }
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("t", sample.axis),
                    yStart: .value("base", span.lowerBound),
                    yEnd: .value("low", sample.low)
                )
                .foregroundStyle(by: .value("band", "LowFill"))
                .interpolationMethod(.monotone)
            }
            ForEach(samples) { sample in
                LineMark(x: .value("t", sample.axis), y: .value("high", sample.high))
                    .foregroundStyle(by: .value("series", "High"))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                LineMark(x: .value("t", sample.axis), y: .value("low", sample.low))
                    .foregroundStyle(by: .value("series", "Low"))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
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
        .chartYScale(domain: span)
        .chartForegroundStyleScale([
            "HighFill": highColor.opacity(0.22),
            "LowFill": lowColor.opacity(0.18),
            "High": highColor,
            "Low": lowColor
        ])
        .chartLegend(position: .top, alignment: .leading) {
            HStack(spacing: 14) {
                seriesKey("High", highColor)
                seriesKey("Low", lowColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .chartYAxisLabel("°F")
        .modifier(ForecastAxisStyle(theme: theme, hourly: hourly))
        .modifier(SeriesScrubber(dates: axes, selection: selection))
        .frame(height: 248)
    }

    private func singleSeriesChart(_ samples: [PlotPoint], series: String, hourly: Bool, domain: ClosedRange<Double>?, unit: String, selection: Binding<Date?>) -> some View {
        let axes = ForecastDates.unique(samples.map(\.axis))
        let selected = selection.wrappedValue.flatMap { axis in samples.first { $0.axis == axis } }
        let color = JWChart.line(series)
        let includeZero = domain?.lowerBound == 0 || series == "precip" || series == "snow" || series == "wind"
        let span = domain ?? chartDomain(samples.map(\.value), includeZero: includeZero)
        return Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("t", sample.axis),
                    yStart: .value("base", span.lowerBound),
                    yEnd: .value("v", sample.value)
                )
                .foregroundStyle(JWChart.area(color))
                .interpolationMethod(.monotone)
                LineMark(x: .value("t", sample.axis), y: .value("v", sample.value))
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
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
        .chartYScale(domain: span)
        .chartYAxisLabel(unit)
        .modifier(ForecastAxisStyle(theme: theme, hourly: hourly))
        .modifier(SeriesScrubber(dates: axes, selection: selection))
        .frame(height: 236)
    }

    private func seriesKey(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.text)
        }
    }

    private func chartDomain(_ values: [Double], includeZero: Bool) -> ClosedRange<Double> {
        let finite = values.filter(\.isFinite)
        guard let lo = finite.min(), let hi = finite.max() else { return 0...1 }
        if includeZero {
            return 0...max(hi * 1.12, 0.05)
        }
        let span = max(hi - lo, 1)
        let pad = span * 0.22
        return (lo - pad)...(hi + pad)
    }

    private var forecastStatus: String? {
        if model.isLoading { return nil }
        if let message = model.errorMessage, !message.isEmpty { return message }
        if model.showsPlacePrompt { return nil }
        return "Forecast will appear here."
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .accessibilityIdentifier("forecast-empty")
    }

    private var hourlyScrubText: String? {
        guard let axis = hourlySelection, let row = model.hourlyRows.first(where: { ForecastDates.sameHour($0.time, axis) }) else { return nil }
        let when = ForecastDisplay.compactClock(row.clock)
        switch hourlyMode {
        case "feelslike":
            return "\(when)  \(ForecastDisplay.temperature(row.feels))"
        case "precip":
            return "\(when)  \(ForecastDisplay.rainDetail(chance: row.precipChance, amount: row.precip))"
        case "wind":
            let speed = ForecastDisplay.milesPerHour(row.wind)
            let dir = row.windDir.map { " \(WindCompass.label($0))" } ?? ""
            let gust = row.windGust.flatMap { $0 >= 1 ? " · gust \(Int($0.rounded()))" : nil } ?? ""
            return "\(when)  \(speed)\(dir)\(gust)"
        case "uv":
            return "\(when)  \(row.uv.map { "UV \(Int($0.rounded()))" } ?? "—")"
        case "humidity":
            return "\(when)  \(ForecastDisplay.percent(row.humidity))"
        case "pressure":
            return "\(when)  \(ForecastDisplay.pressure(hPa: row.pressure))"
        case "snow":
            return "\(when)  \(ForecastDisplay.inches(row.snow ?? 0))"
        case "cloud":
            return "\(when)  \(ForecastDisplay.cloudDetail(low: row.cloudLow ?? 0, mid: row.cloudMid ?? 0, high: row.cloudHigh ?? 0))"
        case "brightness":
            return "\(when)  \(ForecastDisplay.percent(row.brightness))"
        case "niceweather":
            return "\(when)  \(ForecastDisplay.niceScore(row.niceScore))"
        case "moon":
            return "\(when)  \(ForecastDisplay.moonPercent(row.moonPhase))"
        default:
            return "\(when)  \(ForecastDisplay.temperature(row.temp))"
        }
    }

    private var dailyScrubText: String? {
        guard let axis = dailySelection, let day = model.dailyRows.first(where: { ForecastDates.sameDay($0.date, axis) }) else { return nil }
        switch dailySeries {
        case "temp":
            return "\(day.label)  H \(ForecastDisplay.temperature(day.high))  L \(ForecastDisplay.temperature(day.low))"
        case "feelslike":
            return "\(day.label)  H \(ForecastDisplay.temperature(day.feelsHigh))  L \(ForecastDisplay.temperature(day.feelsLow))"
        case "precip":
            return "\(day.label)  \(ForecastDisplay.rainDetail(chance: day.precipChance, amount: day.precip))"
        case "wind":
            return "\(day.label)  \(ForecastDisplay.windDetail(speed: day.wind, gust: day.gust))"
        case "uv":
            return "\(day.label)  \(day.uv.map { "UV \(Int($0.rounded()))" } ?? "—")"
        case "humidity":
            return "\(day.label)  \(ForecastDisplay.percent(day.humidityAvg))"
        case "pressure":
            return "\(day.label)  \(ForecastDisplay.pressure(inHg: day.pressureInHg))"
        case "snow":
            return "\(day.label)  \(ForecastDisplay.inches(day.snowSum))"
        case "cloud":
            return "\(day.label)  \(ForecastDisplay.cloudDetail(low: day.cloudLowAvg, mid: day.cloudMidAvg, high: day.cloudHighAvg))"
        case "brightness":
            return "\(day.label)  \(ForecastDisplay.percent(day.brightness))"
        case "niceweather":
            return "\(day.label)  \(ForecastDisplay.niceScore(day.niceScore))"
        case "moon":
            return "\(day.label)  \(ForecastDisplay.moonPercent(day.moonPhase))"
        default:
            return "\(day.label)  \(ForecastDisplay.temperature(day.high))"
        }
    }

    private func tideReadout(_ date: Date?, curve: [TideExtreme]) -> String? {
        guard let date, let point = nearestTide(date, in: curve) else { return nil }
        return ForecastDisplay.tideReadout(date: point.time, feet: point.value)
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
        case "moon": return "%"
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
        case "moon": return row.moonPhase * 100
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
        case "moon": return day.moonPhase * 100
        default: return day.high ?? 0
        }
    }

    private var hourlyYDomain: ClosedRange<Double>? {
        switch hourlyMode {
        case "humidity", "brightness", "moon": return 0...100
        case "niceweather": return 0...10
        case "uv": return 0...max(1, model.hourlyRows.map { $0.uv ?? 0 }.max() ?? 1)
        default: return nil
        }
    }

    private var dailyYDomain: ClosedRange<Double>? {
        switch dailySeries {
        case "humidity", "brightness", "moon": return 0...100
        case "niceweather": return 0...10
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
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
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
        .chartLegend(position: .top, alignment: .leading, spacing: 8)
        .chartYScale(domain: 0...100)
        .chartYAxisLabel("%")
        .modifier(ForecastAxisStyle(theme: theme, hourly: hourly))
        .modifier(SeriesScrubber(dates: axes, selection: selection))
        .frame(height: 248)
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
            LazyHStack(alignment: .top, spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    let previous = index > 0 ? rows[index - 1] : nil
                    chip(row, previous: previous, emphasized: index == 0)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var showsConditionIcon: Bool {
        mode == "temp" || mode == "feelslike" || mode == "tides"
    }

    private func chip(_ row: HourRow, previous: HourRow?, emphasized: Bool) -> some View {
        let markDay = ForecastDisplay.marksNewDay(stamp: row.time, previous: previous?.time)
        let clock = ForecastDisplay.chipClock(clock: row.clock, stamp: row.time, markDay: markDay)
        let reading = chipReading(row)
        return VStack(spacing: 6) {
            Text(clock)
                .font(.footnote.weight(.medium))
                .foregroundStyle(emphasized ? theme.text : theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if mode == "wind", let dir = row.windDir {
                Image(systemName: "location.north.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .rotationEffect(.degrees(WindCompass.arrowDegrees(dir)))
                    .accessibilityHidden(true)
            } else if showsConditionIcon {
                SVGIconView(fileName: row.iconFile, folder: "weather", pointSize: 32)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            }
            Text(reading.primary)
                .font(.headline.weight(.bold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let secondary = reading.secondary {
                Text(secondary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(minWidth: 76)
        .background(emphasized ? theme.tile : theme.chip, in: RoundedRectangle(cornerRadius: JWMetrics.radiusChip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: JWMetrics.radiusChip, style: .continuous)
                .stroke(emphasized ? theme.cardStroke : theme.chipStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.spoken)
    }

    private func chipReading(_ row: HourRow) -> (primary: String, secondary: String?, spoken: String) {
        let when = ForecastDisplay.chipClock(
            clock: row.clock,
            stamp: row.time,
            markDay: true
        )
        switch mode {
        case "precip":
            let amount = ForecastDisplay.inches(row.precip ?? 0)
            let chance = row.precipChance.map { "\($0)%" }
            return (amount, chance, [when, amount, chance].compactMap { $0 }.joined(separator: ", "))
        case "wind":
            let speed = ForecastDisplay.milesPerHour(row.wind)
            let gust = row.windGust.flatMap { $0 >= 1 ? "Gust \(Int($0.rounded()))" : nil }
            let from = row.windDir.map { "from \(WindCompass.label($0))" }
            return (speed, gust, [when, speed, gust, from].compactMap { $0 }.joined(separator: ", "))
        case "uv":
            let value = row.uv.map { "\(Int($0.rounded()))" } ?? "—"
            let band = row.uvLabel.isEmpty ? nil : row.uvLabel
            return (value, band, [when, "UV \(value)", band].compactMap { $0 }.joined(separator: ", "))
        case "humidity":
            let value = ForecastDisplay.percent(row.humidity)
            return (value, nil, "\(when), humidity \(value)")
        case "pressure":
            let value = ForecastDisplay.pressure(hPa: row.pressure)
            return (value, nil, "\(when), \(value)")
        case "cloud":
            let value = ForecastDisplay.cloudPercent(total: row.cloud, low: row.cloudLow, mid: row.cloudMid, high: row.cloudHigh)
            return (value, nil, "\(when), cloud cover \(value)")
        case "feelslike":
            let value = ForecastDisplay.temperature(row.feels)
            return (value, nil, "\(when), feels like \(value)")
        case "snow":
            let value = ForecastDisplay.inches(row.snow ?? 0)
            return (value, nil, "\(when), snow \(value)")
        case "brightness":
            let value = ForecastDisplay.percent(row.brightness)
            return (value, nil, "\(when), brightness \(value)")
        case "niceweather":
            let value = ForecastDisplay.niceScore(row.niceScore)
            return (value, nil, "\(when), nice weather \(value)")
        case "moon":
            let value = ForecastDisplay.moonPercent(row.moonPhase)
            return (value, nil, "\(when), moon \(value)")
        default:
            let value = ForecastDisplay.temperature(row.temp)
            return (value, nil, "\(when), \(value)")
        }
    }
}

private struct DailyDetailList: View, Equatable {
    let days: [DayRow]
    let theme: JWPalette
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var expandedID: Int?
    @State private var didApplyLaunchDetail = false

    static func == (lhs: DailyDetailList, rhs: DailyDetailList) -> Bool {
        lhs.days == rhs.days
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                if index > 0, index.isMultiple(of: 7) {
                    weekSeparator(index / 7 + 1)
                }
                dayCard(day)
            }
        }
        .onChange(of: days.map(\.id), initial: true) { _, ids in
            guard LaunchArgs.expandsForecastDetail, !didApplyLaunchDetail, let first = ids.first else { return }
            expandedID = first
            didApplyLaunchDetail = true
        }
    }

    private func weekSeparator(_ week: Int) -> some View {
        HStack(spacing: 12) {
            Rectangle().fill(theme.divider).frame(height: 1)
            Text("Week \(week)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.muted)
            Rectangle().fill(theme.divider).frame(height: 1)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func dayCard(_ day: DayRow) -> some View {
        let expanded = expandedID == day.id
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedID = expanded ? nil : day.id
                }
            } label: {
                ViewThatFits(in: .horizontal) {
                    summary(day, stacked: false)
                    summary(day, stacked: true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summarySpoken(day, expanded: expanded))
            .accessibilityHint(expanded ? "Hides the rest of this day" : "Shows the rest of this day")
            .accessibilityIdentifier("forecast-day-header")

            if expanded {
                dayDetail(day)
                    .accessibilityIdentifier("forecast-day-detail")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chip, in: RoundedRectangle(cornerRadius: JWMetrics.radiusChip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: JWMetrics.radiusChip, style: .continuous)
                .stroke(theme.chipStroke, lineWidth: 1)
        )
    }

    private func summary(_ day: DayRow, stacked: Bool) -> some View {
        let parts = day.label.split(separator: " ", maxSplits: 1).map(String.init)
        let weekday = parts.first ?? day.label
        let dateLabel = parts.count > 1 ? parts[1] : day.date
        let cue = ForecastDisplay.precipCue(chance: day.precipChance, amount: day.precip, snow: day.snowSum)
        return Group {
            if stacked {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        dayIcon(day)
                        dateBlock(weekday: weekday, dateLabel: dateLabel)
                        Spacer(minLength: 8)
                        chevron(expanded: expandedID == day.id)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        temps(day)
                        if let cue {
                            Text(cue)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(theme.muted)
                        }
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    dayIcon(day)
                    dateBlock(weekday: weekday, dateLabel: dateLabel)
                    Spacer(minLength: 8)
                    temps(day)
                    if let cue {
                        Text(cue)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(theme.muted)
                            .lineLimit(1)
                    }
                    chevron(expanded: expandedID == day.id)
                }
            }
        }
    }

    private func dayIcon(_ day: DayRow) -> some View {
        SVGIconView(fileName: day.iconFile, folder: "weather", pointSize: 28)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }

    private func dateBlock(weekday: String, dateLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(weekday)
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Text(dateLabel)
                .font(.subheadline)
                .foregroundStyle(theme.muted)
                .lineLimit(1)
        }
        .layoutPriority(1)
    }

    private func temps(_ day: DayRow) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(ForecastDisplay.temperature(day.high))
                .font(.headline.weight(.bold))
                .foregroundStyle(theme.text)
                .monospacedDigit()
            Text(ForecastDisplay.temperature(day.low))
                .font(.subheadline)
                .foregroundStyle(theme.muted)
                .monospacedDigit()
        }
    }

    private func chevron(expanded: Bool) -> some View {
        Image(systemName: "chevron.down")
            .font(.caption.weight(.bold))
            .foregroundStyle(theme.muted)
            .rotationEffect(.degrees(expanded ? 180 : 0))
            .accessibilityHidden(true)
    }

    private func summarySpoken(_ day: DayRow, expanded: Bool) -> String {
        let high = ForecastDisplay.temperature(day.high)
        let low = ForecastDisplay.temperature(day.low)
        let cue = ForecastDisplay.precipCue(chance: day.precipChance, amount: day.precip, snow: day.snowSum)
        let state = expanded ? "expanded" : "collapsed"
        return [day.fullLabel, day.summary, "high \(high)", "low \(low)", cue, state]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func dayDetail(_ day: DayRow) -> some View {
        let rows = detailRows(day)
        return VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(theme.divider)
                .frame(height: 1)
            if !day.summary.isEmpty {
                Text(day.summary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(rows, id: \.label) { row in
                detailLine(row.label, row.value)
            }
        }
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        let stacks = typeSize >= .accessibility1
        return Group {
            if stacks {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).foregroundStyle(theme.muted)
                    Text(value).foregroundStyle(theme.text)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(label)
                        .foregroundStyle(theme.muted)
                    Spacer(minLength: 8)
                    Text(value)
                        .foregroundStyle(theme.text)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func detailRows(_ day: DayRow) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if day.feelsHigh != nil || day.feelsLow != nil {
            rows.append(("Feels like", ForecastDisplay.temperaturePair(day.feelsHigh, day.feelsLow)))
        }
        if day.snowSum > 0 {
            rows.append(("Snow", ForecastDisplay.inches(day.snowSum, places: day.snowSum >= 0.1 ? 1 : 2)))
        }
        rows.append(("Rain", ForecastDisplay.rainDetail(chance: day.precipChance, amount: day.precip)))
        rows.append(("Wind", ForecastDisplay.windDetail(speed: day.wind, gust: day.gust)))
        if let uv = day.uv {
            let band = LogicEngine.shared.uvLabel(uv)
            let number = "\(Int(uv.rounded()))"
            rows.append(("UV", band.isEmpty ? number : "\(number) \(band)"))
        }
        rows.append(("Humidity", ForecastDisplay.percent(day.humidityAvg)))
        let sun = [day.sunriseClock, day.sunsetClock].filter { !$0.isEmpty }
        if sun.count == 2 {
            rows.append(("Sun", "\(sun[0]) – \(sun[1])"))
        }
        rows.append(("Pressure", ForecastDisplay.pressure(inHg: day.pressureInHg)))
        rows.append(("Clouds", ForecastDisplay.cloudDetail(low: day.cloudLowAvg, mid: day.cloudMidAvg, high: day.cloudHighAvg)))
        rows.append(("Brightness", ForecastDisplay.percent(day.brightness)))
        rows.append(("Nice weather", ForecastDisplay.niceScore(day.niceScore)))
        rows.append(("Moon", ForecastDisplay.moonPercent(day.moonPhase)))
        return rows
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
        ForecastDisplay.axisLabel(date: date, hourly: hourly)
    }
}

private struct ForecastAxisStyle: ViewModifier {
    let theme: JWPalette
    let hourly: Bool

    func body(content: Content) -> some View {
        content
            .chartPlotStyle { $0.background(.clear) }
            .chartXAxis {
                AxisMarks(values: .stride(by: hourly ? .hour : .day, count: hourly ? 6 : 2, calendar: ForecastDates.calendar)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 3])).foregroundStyle(theme.grid)
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) {
                            Text(ForecastDates.axisLabel(date, hourly: hourly))
                                .font(.caption2.weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(theme.text.opacity(0.92))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 3])).foregroundStyle(theme.grid)
                    AxisValueLabel()
                        .foregroundStyle(theme.text.opacity(0.82))
                        .font(.caption2.weight(.medium))
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
