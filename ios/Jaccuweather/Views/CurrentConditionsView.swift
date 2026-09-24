import SwiftUI

struct CurrentConditionsView: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var showMoon = false
    @State private var selectedAlert: NWSAlertFeature?

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        TabScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let message = model.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.orange)
                }
                if let note = model.statusNote {
                    Text(note).font(.footnote).foregroundStyle(theme.muted)
                }
                if !model.alerts.isEmpty { alertsCard }
                atmosphere
                health
                pollen
                if let tides = model.tides { tidesCard(tides) }
            }
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
        let desc = LogicEngine.shared.weatherDescription(current?.int("weather_code"))
        let isDay = current?.int("is_day") != 0
        let icon = LogicEngine.shared.weatherIconFile(code: current?.int("weather_code"), isDay: isDay)
        return WeatherCard(title: model.locationName) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(temp(current?.number("temperature_2m")))
                        .font(.system(size: 64, weight: .light, design: .rounded))
                    Text(desc).font(.title3.weight(.medium))
                    if let today = model.dailyRows.first {
                        Text("H:\(int(today.high))°  L:\(int(today.low))°").foregroundStyle(theme.muted)
                    }
                    Text(model.precipTiming).font(.caption).foregroundStyle(theme.muted)
                    if !model.lastUpdatedLabel.isEmpty {
                        Text("Updated \(model.lastUpdatedLabel)").font(.caption2).foregroundStyle(theme.muted)
                    }
                }
                Spacer()
                SVGIconView(fileName: icon, folder: "weather", pointSize: 72)
                    .frame(width: 72, height: 72)
            }
            if let today = model.dailyRows.first {
                SunArcView(
                    sunriseIso: today.sunrise ?? "",
                    sunsetIso: today.sunset ?? "",
                    utcOffset: model.weather?.utcOffset ?? 0
                )
                .padding(.top, 8)
            }
        }
    }

    private var atmosphere: some View {
        let current = model.weather?.current
        let pressure = model.pressureDisplay
        let moon = model.moon
        let today = model.dailyRows.first
        return WeatherCard(title: "Atmosphere") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metric("Feels like", temp(current?.number("apparent_temperature")), "thermometer")
                metric("Humidity", current?.int("relative_humidity_2m").map { "\($0)%" } ?? "—", "humidity")
                windMetric(current)
                metric("UV", current?.number("uv_index").map { String(format: "%.0f · %@", $0, LogicEngine.shared.uvLabel($0)) } ?? "—", "uv-index")
                metric("Pressure", "\(pressure.value) \(pressure.trend)", "barometer")
                metric("Dew point", temp(current?.number("dewpoint_2m")), "humidity")
                metric("Sunrise", today?.sunrise.map { LogicEngine.shared.string("formatIsoLocalClock", [$0]) ?? $0 } ?? "—", "sunrise")
                metric("Sunset", today?.sunset.map { LogicEngine.shared.string("formatIsoLocalClock", [$0]) ?? $0 } ?? "—", "sunrise")
            }
            Button { showMoon = true } label: {
                HStack {
                    SVGIconView(fileName: "starry-night.svg", folder: "cards", pointSize: 22).frame(width: 22, height: 22)
                    Text("\(moon.emoji)  \(moon.name)")
                    Spacer()
                    Text("Rise \(moon.rise) · Set \(moon.set)").font(.caption).foregroundStyle(theme.muted)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var health: some View {
        guard let weather = model.weather else { return AnyView(EmptyView()) }
        let sinus = HealthScores.sinus(from: weather)
        let allergy = HealthScores.allergy(pollen: model.pollen, weather: weather)
        let nice = HealthScores.niceWeather(from: weather)
        return AnyView(WeatherCard(title: "Health") {
            HStack(spacing: 10) {
                NavigationLink { MethodologySheet(kind: .sinus, weather: weather, pollen: model.pollen) } label: {
                    riskTile("Sinus", sinus.label, sinus.detail)
                }
                NavigationLink { MethodologySheet(kind: .allergy, weather: weather, pollen: model.pollen) } label: {
                    riskTile("Allergy", allergy.label, allergy.detail)
                }
                NavigationLink { MethodologySheet(kind: .nice, weather: weather, pollen: model.pollen) } label: {
                    riskTile("Nice", nice.score.map { "\($0)/10" } ?? "—", nice.label)
                }
            }
        })
    }

    private var pollen: some View {
        guard let pollen = model.pollen else {
            return AnyView(WeatherCard(title: "Pollen") { Text("Open-Meteo fallback (no Google/Tomorrow keys).").foregroundStyle(theme.muted) })
        }
        let current = pollen.map("current")
        let tree = LogicEngine.shared.number("maxAvailablePollen", [[current.number("tree_pollen") as Any, current.number("alder_pollen") as Any, current.number("birch_pollen") as Any, current.number("olive_pollen") as Any]])
        let grass = current.number("grass_pollen")
        let weed = LogicEngine.shared.number("maxAvailablePollen", [[current.number("weed_pollen") as Any, current.number("mugwort_pollen") as Any, current.number("ragweed_pollen") as Any]])
        return AnyView(WeatherCard(title: "Pollen · \(pollen.string("pollen_source") ?? "open-meteo")") {
            HStack {
                pollenCol("Tree", tree, "pollen-tree")
                pollenCol("Grass", grass, "pollen-grass")
                pollenCol("Weed", weed, "pollen-weed")
            }
            if let aqi = current.number("us_aqi") {
                let label = aqiLabel(aqi)
                HStack(spacing: 8) {
                    SVGIconView(fileName: "smoke.svg", folder: "cards", pointSize: 18).frame(width: 18, height: 18)
                    Text("US AQI \(Int(aqi.rounded())) · \(label)").font(.caption).foregroundStyle(theme.muted)
                }
            }
            speciesRow(current)
            Text("Tree: Alder, Birch, Olive  ·  Grass: general  ·  Weed: Mugwort, Ragweed")
                .font(.caption2)
                .foregroundStyle(theme.muted)
        })
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
                            SVGIconView(fileName: LogicEngine.shared.alertIconFile(alert.properties.event), folder: "alerts", pointSize: 28)
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

    private func pollenCol(_ name: String, _ value: Double?, _ icon: String) -> some View {
        let level = JSONMap(LogicEngine.shared.object("getPollenLevel", [value as Any]))
        return VStack {
            SVGIconView(fileName: icon + ".svg", folder: "cards", pointSize: 22).frame(width: 22, height: 22)
            Text(name).font(.caption).foregroundStyle(theme.muted)
            Text(value.map { "\(Int($0.rounded()))" } ?? "n/a").font(.headline)
            Text(level.string("label") ?? "None").font(.caption2)
        }
        .frame(maxWidth: .infinity)
    }

    private func speciesRow(_ current: JSONMap) -> some View {
        let fields = [
            ("Alder", "alder_pollen"),
            ("Birch", "birch_pollen"),
            ("Olive", "olive_pollen"),
            ("Mugwort", "mugwort_pollen"),
            ("Ragweed", "ragweed_pollen")
        ]
        return VStack(alignment: .leading, spacing: 6) {
            Text("Species").font(.caption.weight(.semibold)).foregroundStyle(theme.muted)
            ForEach(fields, id: \.0) { name, key in
                let value = current.number(key)
                let shown = LogicEngine.shared.string("formatPollenValue", [value as Any]) ?? "n/a"
                HStack {
                    Text(name)
                    Spacer()
                    Text(shown)
                    Text(JSONMap(LogicEngine.shared.object("getPollenLevel", [value as Any])).string("label") ?? "")
                        .foregroundStyle(theme.muted)
                }
                .font(.caption)
            }
        }
        .padding(.top, 8)
    }

    private func riskTile(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(theme.muted)
            Text(value).font(.headline)
            Text(detail).font(.caption2).foregroundStyle(theme.muted).lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func windMetric(_ current: JSONMap?) -> some View {
        let speed = current?.number("wind_speed_10m")
        let gust = current?.number("wind_gusts_10m")
        let dir = current?.number("wind_direction_10m")
        let speedText = speed.map { String(format: "%.0f mph", $0) } ?? "—"
        let detail: String = {
            var parts: [String] = []
            if let dir { parts.append(WindCompass.label(dir)) }
            if let gust { parts.append(String(format: "G%.0f", gust)) }
            return parts.joined(separator: " · ")
        }()
        return HStack(alignment: .top, spacing: 8) {
            SVGIconView(fileName: "wind.svg", folder: "cards", pointSize: 18).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("Wind").font(.caption).foregroundStyle(theme.muted)
                HStack(spacing: 6) {
                    if let dir {
                        Image(systemName: "location.north.fill")
                            .font(.caption)
                            .rotationEffect(.degrees(WindCompass.arrowDegrees(dir)))
                            .accessibilityLabel("Wind from \(WindCompass.label(dir))")
                    }
                    Text(speedText).font(.subheadline.weight(.semibold))
                }
                if !detail.isEmpty {
                    Text(detail).font(.caption2).foregroundStyle(theme.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metric(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            SVGIconView(fileName: icon + ".svg", folder: "cards", pointSize: 18).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(theme.muted)
                Text(value).font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "extreme", "severe": return .red
        case "moderate": return .orange
        case "minor": return theme.gold
        default: return theme.muted
        }
    }

    private func aqiLabel(_ value: Double) -> String {
        switch Int(value.rounded()) {
        case ..<51: return "Good"
        case ..<101: return "Moderate"
        case ..<151: return "Unhealthy for sensitive groups"
        case ..<201: return "Unhealthy"
        case ..<301: return "Very unhealthy"
        default: return "Hazardous"
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
    let sunriseIso: String
    let sunsetIso: String
    let utcOffset: Int

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let sample = sunSample(at: context.date)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SUNRISE").font(.caption2).foregroundStyle(theme.muted)
                    Text(LogicEngine.shared.string("formatIsoLocalClock", [sunriseIso]) ?? sunriseIso)
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
                    Text(LogicEngine.shared.string("formatIsoLocalClock", [sunsetIso]) ?? sunsetIso)
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
        let rise = LogicEngine.shared.number("parseLocationLocalIso", [sunriseIso, utcOffset]) ?? 0
        let set = LogicEngine.shared.number("parseLocationLocalIso", [sunsetIso, utcOffset]) ?? 0
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

