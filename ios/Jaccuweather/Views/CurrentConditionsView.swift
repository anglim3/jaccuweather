import SwiftUI

struct CurrentConditionsView: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var showMoon = false
    @State private var selectedAlert: NWSAlertFeature?

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        TabScreenScroll {
            // Pollen (and its AQI) arrives after the forecast. Keep the Now
            // column in one stack so the air-quality row is not a lazy insert.
            VStack(alignment: .leading, spacing: JWMetrics.sectionGap) {
            if !model.alerts.isEmpty {
                alertsCard
            } else if model.alertsFailed {
                WeatherCard(title: "NWS alerts") {
                    Text("Alerts are unavailable right now.")
                        .font(JWFont.body)
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("nws-alerts-unavailable")
                }
            }
            header
            if let aqi = USAQIDisplay.from(current: model.pollen?.map("current")) {
                AirQualityCard(reading: aqi, compact: true)
            }
            if let message = model.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.orange)
            }
            if let note = model.statusNote {
                Text(note).font(.footnote).foregroundStyle(theme.muted)
            }
            if !model.precipTiming.isEmpty { precipCard }
            if let snow = model.weeklySnow, !snow.periods.isEmpty { snowCard(snow) }
            moonCard
            if let tides = model.tides { tidesCard(tides) }
            }
        }
        .navigationTitle("Now")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { model.requestDeviceLocation() } label: { Image(systemName: "location.fill") }
            }
            ToolbarItem(placement: .topBarLeading) {
                ShareConditionsButton(reading: shareReading)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.favorites.toggle(model.currentPlace) } label: {
                    Image(systemName: model.favorites.contains(model.currentPlace) ? "star.fill" : "star")
                        .foregroundStyle(theme.gold)
                }
            }
        }
        .refreshable { await model.refresh() }
        .onAppear {
            if let alert = model.routedAlert { selectedAlert = alert }
        }
        .onChange(of: model.routedAlert?.id) { _, id in
            guard id != nil, let alert = model.routedAlert else { return }
            selectedAlert = alert
        }
        .onChange(of: model.alerts.map(\.id)) { _, ids in
            guard let selected = selectedAlert else { return }
            if ids.contains(selected.id) { return }
            if model.routedAlert?.id == selected.id { return }
            selectedAlert = nil
        }
        .sheet(isPresented: $showMoon) { MoonSheet() }
        .sheet(item: $selectedAlert, onDismiss: { model.clearRoutedAlert() }) { alert in
            AlertDetailSheet(alert: alert)
        }
    }

    private var header: some View {
        let current = model.weather?.current
        let sun = model.sun
        let pressure = model.pressureDisplay
        let uvValue = current?.number("uv_index")
        let uvText = uvValue.map { String(format: "%.0f", $0) } ?? "—"
        let uvDetail = model.currentUVDetail.isEmpty ? nil : model.currentUVDetail
        let humidity = current?.int("relative_humidity_2m").map { "\($0)%" } ?? "—"
        let dew = temp(current?.number("dewpoint_2m"))
        return WeatherCard(title: "", prominence: .hero) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.locationName.isEmpty ? " " : model.locationName)
                    .font(JWFont.location)
                    .tracking(-0.6)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if model.weather != nil {
                    dateLine
                }
            }

            HStack(alignment: .center, spacing: 10) {
                SVGIconView(fileName: model.conditionIcon, folder: "weather", pointSize: 52)
                    .frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                Text(temp(current?.number("temperature_2m")))
                    .font(JWFont.heroTemp)
                    .tracking(-2.7)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .layoutPriority(1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.conditionDescription)
                        .font(.body)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    if let sun {
                        Text("\(int(sun.high))°/\(int(sun.low))°")
                            .font(.subheadline)
                            .foregroundStyle(theme.muted)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }

            if let sun {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(theme.divider)
                        .frame(height: 1)
                    SunArcView(sun: sun)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    metricCell(title: "Feels Like", value: temp(current?.number("apparent_temperature")), icon: "thermometer")
                    metricCell(title: "Humidity", value: humidity, detail: "Dew: \(dew)", icon: "humidity")
                }
                HStack(alignment: .top, spacing: 16) {
                    windCell(current)
                    metricCell(title: "UV Index", value: uvText, detail: uvDetail, icon: "uv-index")
                }
                Rectangle()
                    .fill(theme.divider)
                    .frame(height: 1)
                    .padding(.vertical, 2)
                pressureRow(value: pressure.value, trend: pressure.trend)
            }
        }
    }

    private var shareReading: ConditionsShareReading {
        let current = model.weather?.current
        return ConditionsShareReading(
            placeName: model.locationName,
            temperatureF: current?.number("temperature_2m"),
            feelsLikeF: current?.number("apparent_temperature"),
            conditionText: model.conditionDescription,
            highF: model.sun?.high,
            lowF: model.sun?.low
        )
    }

    private var locationDateLine: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d"
        formatter.timeZone = TimeZone(secondsFromGMT: model.weather?.utcOffset ?? 0)
        return formatter.string(from: Date())
    }

    /// Date and freshness share one line so the hero does not stack two captions.
    private var dateLine: some View {
        let updated = model.lastUpdatedLabel
        return Group {
            if updated.isEmpty {
                Text(locationDateLine)
                    .foregroundStyle(theme.muted)
            } else {
                (Text(locationDateLine).foregroundStyle(theme.muted)
                    + Text("  ·  Updated \(updated)").foregroundStyle(theme.faint))
            }
        }
        .font(.subheadline)
        .lineLimit(2)
        .minimumScaleFactor(0.85)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var precipCard: some View {
        HStack(alignment: .center, spacing: 12) {
            SVGIconView(fileName: "overcast-day-rain.svg", folder: "weather", pointSize: 28)
                .frame(width: 28, height: 28)
            Text(model.precipTiming)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jwGlass(.panel)
    }

    private func snowCard(_ snow: WeeklySnowSummary) -> some View {
        WeatherCard(title: "Weekly Snow Totals") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(snow.periods) { period in
                    snowPeriod(period)
                }
                if let nwsLine = snow.nwsLine {
                    Text(nwsLine)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.faint)
                        .padding(.top, 4)
                        .accessibilityIdentifier("weekly-snow-nws")
                }
            }
        }
        .accessibilityIdentifier("weekly-snow-card")
    }

    private func snowPeriod(_ period: SnowPeriod) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(period.headline)
                .font(JWFont.dayName)
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let breakdown = period.breakdown {
                Text(breakdown)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chip, in: RoundedRectangle(cornerRadius: JWMetrics.radiusChip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: JWMetrics.radiusChip, style: .continuous)
                .stroke(theme.chipStroke, lineWidth: 1)
        )
    }

    private var moonCard: some View {
        let moon = model.moon
        return WeatherCard(title: "Moon") {
            Button { showMoon = true } label: {
                HStack(alignment: .center, spacing: 12) {
                    Text(moon.emoji)
                        .font(.title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(minWidth: 36, minHeight: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(moon.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(moon.illumination) illuminated")
                            .font(.subheadline)
                            .foregroundStyle(theme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("Rise \(moon.rise)  ·  Set \(moon.set)")
                            .font(.subheadline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Full \(moon.nextFull)  ·  New \(moon.nextNew)")
                            .font(.caption)
                            .foregroundStyle(theme.muted)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.muted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("moon-card")
            .accessibilityLabel("\(moon.name), \(moon.illumination) illuminated. Rise \(moon.rise), set \(moon.set)")
        }
    }

    private func tidesCard(_ tides: TideSnapshot) -> some View {
        WeatherCard(title: "Tides · \(tides.station.name)") {
            ForEach(tides.extremes.prefix(6)) { extreme in
                HStack {
                    Text(extreme.type == "H" ? "High" : "Low")
                    Spacer()
                    Text(String(format: "%.1f ft", extreme.value))
                    Text(LogicEngine.shared.string("formatTime12Hour", [extreme.time]) ?? "")
                        .foregroundStyle(theme.muted)
                }
                .font(.subheadline)
            }
        }
    }

    private var alertsCard: some View {
        WeatherCard(title: "NWS alerts") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.alerts.prefix(5)) { alert in
                    Button { selectedAlert = alert } label: {
                        HStack(alignment: .top, spacing: 10) {
                            SVGIconView(fileName: model.alertIconFiles[alert.properties.event ?? ""] ?? "weather-alarm.svg", folder: "alerts", pointSize: 28)
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alert.properties.event ?? "Alert").font(.subheadline.weight(.semibold))
                                if let severity = alert.properties.severity {
                                    Text(severity).font(.caption2.weight(.semibold)).foregroundStyle(severityColor(severity))
                                }
                                Text(alert.properties.headline ?? "").font(.caption).foregroundStyle(theme.muted).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Link(destination: APIEndpoints.noaaRadarCredit) {
                    Text("Alerts from NOAA / NWS")
                        .font(.caption.weight(.semibold))
                        .underline()
                }
                .accessibilityIdentifier("nws-alerts-credit")
            }
        }
        .tint(theme.accent)
    }

    private func metricCell(title: String, value: String, detail: String? = nil, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            metricLabel(title, icon: icon)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(theme.faint)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func metricLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            SVGIconView(fileName: icon + ".svg", folder: "cards", pointSize: 16)
                .frame(width: 16, height: 16)
            Text(title)
                .font(.caption)
                .foregroundStyle(theme.faint)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func windCell(_ current: JSONMap?) -> some View {
        let speed = current?.number("wind_speed_10m")
        let gust = current?.number("wind_gusts_10m")
        let dir = current?.number("wind_direction_10m")
        let speedText = speed.map { String(format: "%.0f mph", $0) } ?? "—"
        let detail: String = {
            var parts: [String] = []
            if let dir { parts.append("From \(WindCompass.label(dir))") }
            if let gust { parts.append(String(format: "Gust %.0f", gust)) }
            return parts.joined(separator: " · ")
        }()
        let spoken = [speedText, detail].filter { !$0.isEmpty }.joined(separator: ", ")
        return HStack(alignment: .center, spacing: 4) {
            metricCell(title: "Wind", value: speedText, detail: detail.isEmpty ? nil : detail, icon: "wind")
            if let dir {
                Image(systemName: "location.north.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .rotationEffect(.degrees(WindCompass.arrowDegrees(dir)))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wind, \(spoken)")
    }

    private func pressureRow(value: String, trend: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            metricLabel("Pressure", icon: "barometer")
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(trend)
                .font(.caption.weight(.medium))
                .foregroundStyle(trend == "Falling" ? theme.gold : theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    private func severityColor(_ severity: String) -> Color {
        AlertSeverity.color(severity, gold: theme.gold, muted: theme.muted)
    }

    private func temp(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))°"
    }

    private func int(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))"
    }
}

struct SunArcView: View {
    @Environment(\.colorScheme) private var colorScheme
    let sun: SunSnapshot

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let sample = sunSample(at: context.date)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SUNRISE")
                        .font(.caption2.weight(.medium))
                        .tracking(0.7)
                        .foregroundStyle(theme.faint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(sun.sunriseLabel)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: 88, alignment: .leading)
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let point = ellipsePoint(t: sample.progress, width: w, height: h)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: h))
                        for step in 1...48 {
                            let t = CGFloat(step) / 48
                            path.addLine(to: ellipsePoint(t: t, width: w, height: h))
                        }
                    }
                    .stroke(theme.sunStroke, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    Circle()
                        .fill(sample.isDay ? theme.gold : theme.moon)
                        .frame(width: 12, height: 12)
                        .shadow(color: (sample.isDay ? theme.gold : theme.moon).opacity(0.55), radius: 6)
                        .position(point)
                        .accessibilityLabel(sample.isDay ? "Sun position" : "Moon, sun is down")
                }
                .frame(height: 48)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("SUNSET")
                        .font(.caption2.weight(.medium))
                        .tracking(0.7)
                        .foregroundStyle(theme.faint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(sun.sunsetLabel)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: 88, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Same half-ellipse as the website SVG (`M 0 100 A 500 100 0 0 1 1000 100`).
    /// theta runs PI at sunrise to 0 at sunset so the marker center sits on the stroke.
    private func ellipsePoint(t: CGFloat, width: CGFloat, height: CGFloat) -> CGPoint {
        let theta = Double.pi * (1 - Double(t))
        let x = width * (0.5 + 0.5 * CGFloat(cos(theta)))
        let y = height * (1 - CGFloat(sin(theta)))
        return CGPoint(x: x, y: y)
    }

    private func sunSample(at date: Date) -> (progress: CGFloat, isDay: Bool) {
        let now = date.timeIntervalSince1970 * 1000
        let rise = sun.sunriseMs
        let set = sun.sunsetMs
        if set <= rise { return (0, false) }
        if now <= rise { return (0, false) }
        if now >= set { return (1, false) }
        return (CGFloat((now - rise) / (set - rise)), true)
    }
}

enum AlertSeverity {
    static func color(_ severity: String, gold: Color, muted: Color) -> Color {
        switch severity.lowercased() {
        case "extreme", "severe": return .red
        case "moderate": return .orange
        case "minor": return gold
        default: return muted
        }
    }
}

struct AlertDetailSheet: View {
    let alert: NWSAlertFeature
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        SVGIconView(fileName: LogicEngine.shared.alertIconFile(alert.properties.event), folder: "alerts", pointSize: 36)
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(alert.properties.event ?? "Alert")
                                .font(.title3.weight(.semibold))
                                .accessibilityIdentifier("alert-detail-event")
                            if let severity = alert.properties.severity {
                                Text([severity, alert.properties.urgency].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AlertSeverity.color(severity, gold: theme.gold, muted: theme.muted))
                            }
                        }
                    }
                    if let headline = alert.properties.headline {
                        Text(headline).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                    if let sender = alert.properties.senderName {
                        Text(sender).font(.caption).foregroundStyle(theme.muted)
                    }
                    if let schedule = alert.scheduleLine {
                        Text(schedule)
                            .font(.caption)
                            .foregroundStyle(theme.muted)
                            .accessibilityIdentifier("alert-detail-ends")
                    }
                    if let description = alert.properties.description, !description.isEmpty {
                        Text(description).font(.body)
                    }
                    if let instruction = alert.properties.instruction, !instruction.isEmpty {
                        Text(instruction)
                            .font(.subheadline)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Link(destination: APIEndpoints.noaaRadarCredit) {
                        Text("Alerts from NOAA / NWS")
                            .font(.caption.weight(.semibold))
                            .underline()
                    }
                }
                .padding(16)
                .foregroundStyle(theme.text)
            }
            .tint(theme.accent)
            .background { HorizonBackground() }
            .navigationTitle("Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

