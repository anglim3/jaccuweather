import SwiftUI

struct CurrentConditionsView: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var showMoon = false
    @State private var selectedAlert: NWSAlertFeature?

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        TabScreenScroll {
            header
            if let message = model.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.orange)
            }
            if let note = model.statusNote {
                Text(note).font(.footnote).foregroundStyle(theme.muted)
            }
            if !model.alerts.isEmpty { alertsCard }
            atmosphere
            if let snow = model.weeklySnow, !snow.periods.isEmpty { snowCard(snow) }
            moonCard
            if let tides = model.tides { tidesCard(tides) }
        }
        .navigationTitle("Now")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { model.requestDeviceLocation() } label: { Image(systemName: "location.fill") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.favorites.toggle(model.currentPlace) } label: {
                    Image(systemName: model.favorites.contains(model.currentPlace) ? "star.fill" : "star")
                        .foregroundStyle(theme.gold)
                }
            }
        }
        .refreshable { await model.refresh() }
        .sheet(isPresented: $showMoon) { MoonSheet() }
        .sheet(item: $selectedAlert) { alert in
            AlertDetailSheet(alert: alert)
        }
    }

    private var header: some View {
        let current = model.weather?.current
        let sun = model.sun
        return WeatherCard(title: model.locationName) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(temp(current?.number("temperature_2m")))
                        .font(.system(size: 64, weight: .light, design: .rounded))
                    Text(model.conditionDescription).font(.title3.weight(.medium))
                    if let sun {
                        Text("H:\(int(sun.high))°  L:\(int(sun.low))°").foregroundStyle(theme.muted)
                    }
                    Text(model.precipTiming).font(.caption).foregroundStyle(theme.muted)
                    if !model.lastUpdatedLabel.isEmpty {
                        Text("Updated \(model.lastUpdatedLabel)").font(.caption2).foregroundStyle(theme.muted)
                    }
                }
                Spacer()
                SVGIconView(fileName: model.conditionIcon, folder: "weather", pointSize: 72)
                    .frame(width: 72, height: 72)
            }
            if let sun {
                SunArcView(sun: sun)
                    .frame(height: 64)
                    .padding(.top, 8)
            }
        }
    }

    private var atmosphere: some View {
        let current = model.weather?.current
        let pressure = model.pressureDisplay
        let sun = model.sun
        let uvValue = current?.number("uv_index")
        let uvText = uvValue.map { String(format: "%.0f", $0) } ?? "—"
        let uvDetail = model.currentUVDetail.isEmpty ? nil : model.currentUVDetail
        return VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                metricCard("Feels like", temp(current?.number("apparent_temperature")), icon: "thermometer")
                metricCard("Dew point", temp(current?.number("dewpoint_2m")), icon: "humidity")
            }
            windCard(current)
            HStack(alignment: .top, spacing: 12) {
                metricCard("Humidity", current?.int("relative_humidity_2m").map { "\($0)%" } ?? "—", icon: "humidity")
                metricCard("UV", uvText, detail: uvDetail, icon: "uv-index")
            }
            pressureCard(value: pressure.value, trend: pressure.trend)
            HStack(alignment: .top, spacing: 12) {
                metricCard("Sunrise", sun?.sunriseLabel ?? "—", icon: "sunrise")
                metricCard("Sunset", sun?.sunsetLabel ?? "—", icon: "clear-day")
            }
        }
    }

    private func snowCard(_ snow: WeeklySnowSummary) -> some View {
        WeatherCard(title: "Weekly Snow Totals") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(snow.periods) { period in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(period.headline)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        if let breakdown = period.breakdown {
                            Text(breakdown)
                                .font(.caption)
                                .foregroundStyle(theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let nwsLine = snow.nwsLine {
                    Text(nwsLine)
                        .font(.caption)
                        .foregroundStyle(theme.muted)
                        .padding(.top, 2)
                        .accessibilityIdentifier("weekly-snow-nws")
                }
            }
        }
        .accessibilityIdentifier("weekly-snow-card")
    }

    private var moonCard: some View {
        let moon = model.moon
        return WeatherCard(title: "Moon") {
            Button { showMoon = true } label: {
                HStack(alignment: .center, spacing: 14) {
                    Text(moon.emoji)
                        .font(.system(size: 52))
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(moon.name).font(.title3.weight(.semibold))
                        Text("\(moon.illumination) illuminated")
                            .font(.subheadline)
                            .foregroundStyle(theme.muted)
                        Text("Rise \(moon.rise)  ·  Set \(moon.set)")
                            .font(.subheadline)
                        Text("Full \(moon.nextFull)  ·  New \(moon.nextNew)")
                            .font(.caption)
                            .foregroundStyle(theme.muted)
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
            }
        }
    }

    private func metricCard(_ title: String, _ value: String, detail: String? = nil, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SVGIconView(fileName: icon + ".svg", folder: "cards", pointSize: 44)
                .frame(width: 48, height: 48)
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.muted)
                .tracking(0.6)
                .lineLimit(1)
            Text(value)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail ?? " ")
                .font(.subheadline)
                .foregroundStyle(detail == nil ? Color.clear : theme.muted)
                .lineLimit(1)
                .accessibilityHidden(detail == nil)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.cardStroke, lineWidth: 1)
        )
    }

    private func windCard(_ current: JSONMap?) -> some View {
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
        return HStack(alignment: .center, spacing: 16) {
            SVGIconView(fileName: "wind.svg", folder: "cards", pointSize: 52)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("WIND")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.muted)
                    .tracking(0.6)
                Text(speedText)
                    .font(.title.weight(.semibold))
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 8)
            if let dir {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .rotationEffect(.degrees(WindCompass.arrowDegrees(dir)))
                    .accessibilityLabel("Wind from \(WindCompass.label(dir))")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.cardStroke, lineWidth: 1)
        )
    }

    private func pressureCard(value: String, trend: String) -> some View {
        HStack(alignment: .center, spacing: 16) {
            SVGIconView(fileName: "barometer.svg", folder: "cards", pointSize: 52)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("PRESSURE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.muted)
                    .tracking(0.6)
                Text(value)
                    .font(.title.weight(.semibold))
                Text(trend)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(trend == "Falling" ? theme.gold : theme.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.cardStroke, lineWidth: 1)
        )
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "extreme", "severe": return .red
        case "moderate": return .orange
        case "minor": return theme.gold
        default: return theme.muted
        }
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
                    Text("SUNRISE").font(.caption2).foregroundStyle(theme.muted)
                    Text(sun.sunriseLabel)
                        .font(.caption.weight(.semibold))
                }
                .frame(width: 72, alignment: .leading)
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
                        .shadow(color: (sample.isDay ? theme.gold : theme.moon).opacity(0.7), radius: 6)
                        .position(point)
                        .accessibilityLabel(sample.isDay ? "Sun position" : "Moon, sun is down")
                }
                .frame(height: 48)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("SUNSET").font(.caption2).foregroundStyle(theme.muted)
                    Text(sun.sunsetLabel)
                        .font(.caption.weight(.semibold))
                }
                .frame(width: 72, alignment: .trailing)
            }
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
                            Text(alert.properties.event ?? "Alert").font(.title3.weight(.semibold))
                            if let severity = alert.properties.severity {
                                Text([severity, alert.properties.urgency].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(theme.gold)
                            }
                        }
                    }
                    if let headline = alert.properties.headline {
                        Text(headline).font(.subheadline)
                    }
                    if let sender = alert.properties.senderName {
                        Text(sender).font(.caption).foregroundStyle(theme.muted)
                    }
                    if let ends = alert.properties.ends {
                        Text("Ends \(ends)").font(.caption).foregroundStyle(theme.muted)
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
                }
                .padding(16)
                .foregroundStyle(theme.text)
            }
            .background(theme.background.ignoresSafeArea())
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

