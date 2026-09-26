import SwiftUI

struct CurrentConditionsView: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var showMoon = false
    @State private var selectedAlert: NWSAlertFeature?

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        TabScreenScroll {
            if !model.alerts.isEmpty { alertsCard }
            header
            if let message = model.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.orange)
            }
            if let note = model.statusNote {
                Text(note).font(.footnote).foregroundStyle(theme.muted)
            }
            if !model.precipTiming.isEmpty { precipCard }
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
                    Text(locationDateLine)
                        .font(.subheadline)
                        .foregroundStyle(theme.muted)
                }
                if !model.lastUpdatedLabel.isEmpty {
                    Text("Updated \(model.lastUpdatedLabel)")
                        .font(.caption)
                        .foregroundStyle(theme.faint)
                        .padding(.top, 2)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                SVGIconView(fileName: model.conditionIcon, folder: "weather", pointSize: 56)
                    .frame(width: 56, height: 56)
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
                        .font(.system(size: 17))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if let sun {
                        Text("\(int(sun.high))°/\(int(sun.low))°")
                            .font(.subheadline)
                            .foregroundStyle(theme.muted)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 14)

            if let sun {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(theme.divider)
                        .frame(height: 1)
                    SunArcView(sun: sun)
                        .frame(height: 48)
                        .padding(.top, 14)
                }
                .padding(.top, 16)
            }

            SectionEyebrow(title: "Conditions")
                .padding(.top, 14)
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    statTile(title: "Feels Like", value: temp(current?.number("apparent_temperature")), icon: "thermometer")
                    statTile(title: "Humidity", value: humidity, detail: "Dew: \(dew)", icon: "humidity")
                }
                HStack(alignment: .top, spacing: 12) {
                    windTile(current)
                    statTile(title: "UV Index", value: uvText, detail: uvDetail, icon: "uv-index")
                }
            }

            SectionEyebrow(title: "Atmosphere")
                .padding(.top, 6)
            HStack(alignment: .top, spacing: 12) {
                sunTile(sun)
                pressureTile(value: pressure.value, trend: pressure.trend)
            }
        }
    }

    private var locationDateLine: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d"
        formatter.timeZone = TimeZone(secondsFromGMT: model.weather?.utcOffset ?? 0)
        return formatter.string(from: Date())
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

    private func statTile(title: String, value: String, detail: String? = nil, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            StatLabel(title: title, icon: icon)
            Text(value)
                .font(JWFont.statValue)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail ?? " ")
                .font(.system(size: 12))
                .foregroundStyle(detail == nil ? Color.clear : theme.faint)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .accessibilityHidden(detail == nil)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .jwGlass(.stat)
    }

    private func windTile(_ current: JSONMap?) -> some View {
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
        return HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                StatLabel(title: "Wind", icon: "wind")
                Text(speedText)
                    .font(JWFont.statValue)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail.isEmpty ? " " : detail)
                    .font(.system(size: 12))
                    .foregroundStyle(detail.isEmpty ? Color.clear : theme.faint)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            if let dir {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .rotationEffect(.degrees(WindCompass.arrowDegrees(dir)))
                    .accessibilityLabel("Wind from \(WindCompass.label(dir))")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .jwGlass(.stat)
    }

    private func sunTile(_ sun: SunSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            StatLabel(title: "Sun", icon: "sunrise")
            HStack(spacing: 6) {
                Text("↑").font(.caption).foregroundStyle(theme.gold)
                Text(sun?.sunriseLabel ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                Text("↓").font(.caption).foregroundStyle(.orange)
                Text(sun?.sunsetLabel ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .jwGlass(.stat)
    }

    private func pressureTile(value: String, trend: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            StatLabel(title: "Pressure", icon: "barometer")
            Text(value)
                .font(JWFont.statValue)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(trend)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(trend == "Falling" ? theme.gold : theme.accent)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .jwGlass(.stat)
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
                    Text("SUNRISE")
                        .font(.caption2.weight(.medium))
                        .tracking(0.7)
                        .foregroundStyle(theme.faint)
                    Text(sun.sunriseLabel)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
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
                    Text(sun.sunsetLabel)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
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

