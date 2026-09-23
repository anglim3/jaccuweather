import SwiftUI

struct CurrentConditionsView: View {
    @Environment(WeatherViewModel.self) private var model
    @State private var showMoon = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let message = model.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.orange)
                }
                if !model.alerts.isEmpty { alertsCard }
                atmosphere
                health
                pollen
                if let tides = model.tides { tidesCard(tides) }
            }
            .padding(16)
        }
        .background(JWTheme.background.ignoresSafeArea())
        .navigationTitle("Now")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { model.requestDeviceLocation() } label: { Image(systemName: "location.fill") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.favorites.toggle(model.currentPlace) } label: {
                    Image(systemName: model.favorites.contains(model.currentPlace) ? "star.fill" : "star")
                        .foregroundStyle(JWTheme.gold)
                }
            }
        }
        .refreshable { await model.refresh() }
        .sheet(isPresented: $showMoon) { MoonSheet() }
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
                        Text("H:\(int(today.high))°  L:\(int(today.low))°").foregroundStyle(JWTheme.muted)
                    }
                    Text(model.precipTiming).font(.caption).foregroundStyle(JWTheme.muted)
                    if !model.lastUpdatedLabel.isEmpty {
                        Text("Updated \(model.lastUpdatedLabel)").font(.caption2).foregroundStyle(JWTheme.muted)
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
                .frame(height: 56)
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
                metric("Wind", current?.number("wind_speed_10m").map { String(format: "%.0f mph", $0) } ?? "—", "wind")
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
                    Text("Rise \(moon.rise) · Set \(moon.set)").font(.caption).foregroundStyle(JWTheme.muted)
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
            return AnyView(WeatherCard(title: "Pollen") { Text("Open-Meteo fallback (no Google/Tomorrow keys).").foregroundStyle(JWTheme.muted) })
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
                Text("US AQI \(Int(aqi.rounded()))").font(.caption).foregroundStyle(JWTheme.muted)
            }
            speciesRow(current)
            Text("Tree: Alder, Birch, Olive  ·  Grass: general  ·  Weed: Mugwort, Ragweed")
                .font(.caption2)
                .foregroundStyle(JWTheme.muted)
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
                        .foregroundStyle(JWTheme.muted)
                }
                .font(.subheadline)
            }
        }
    }

    private var alertsCard: some View {
        WeatherCard(title: "NWS alerts") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.alerts.prefix(5)) { alert in
                    HStack(alignment: .top, spacing: 10) {
                        SVGIconView(fileName: LogicEngine.shared.alertIconFile(alert.properties.event), folder: "alerts", pointSize: 28)
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading) {
                            Text(alert.properties.event ?? "Alert").font(.subheadline.weight(.semibold))
                            Text(alert.properties.headline ?? "").font(.caption).foregroundStyle(JWTheme.muted)
                        }
                    }
                }
            }
        }
    }

    private func pollenCol(_ name: String, _ value: Double?, _ icon: String) -> some View {
        let level = JSONMap(LogicEngine.shared.object("getPollenLevel", [value as Any]))
        return VStack {
            SVGIconView(fileName: icon + ".svg", folder: "cards", pointSize: 22).frame(width: 22, height: 22)
            Text(name).font(.caption).foregroundStyle(JWTheme.muted)
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
            Text("Species").font(.caption.weight(.semibold)).foregroundStyle(JWTheme.muted)
            ForEach(fields, id: \.0) { name, key in
                let value = current.number(key)
                let shown = LogicEngine.shared.string("formatPollenValue", [value as Any]) ?? "n/a"
                HStack {
                    Text(name)
                    Spacer()
                    Text(shown)
                    Text(JSONMap(LogicEngine.shared.object("getPollenLevel", [value as Any])).string("label") ?? "")
                        .foregroundStyle(JWTheme.muted)
                }
                .font(.caption)
            }
        }
        .padding(.top, 8)
    }

    private func riskTile(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(JWTheme.muted)
            Text(value).font(.headline)
            Text(detail).font(.caption2).foregroundStyle(JWTheme.muted).lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metric(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            SVGIconView(fileName: icon + ".svg", folder: "cards", pointSize: 18).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(JWTheme.muted)
                Text(value).font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    let sunriseIso: String
    let sunsetIso: String
    let utcOffset: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let t = progress
            VStack(spacing: 4) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: h - 2))
                        path.addQuadCurve(to: CGPoint(x: w, y: h - 2), control: CGPoint(x: w / 2, y: 2))
                    }
                    .stroke(JWTheme.gold.opacity(0.85), lineWidth: 2)
                    Circle()
                        .fill(JWTheme.gold)
                        .frame(width: 10, height: 10)
                        .position(x: w * t, y: (h - 2) - sin(t * .pi) * (h - 8))
                }
                HStack {
                    Text(LogicEngine.shared.string("formatIsoLocalClock", [sunriseIso]) ?? sunriseIso)
                    Spacer()
                    Text(LogicEngine.shared.string("formatIsoLocalClock", [sunsetIso]) ?? sunsetIso)
                }
                .font(.caption2)
                .foregroundStyle(JWTheme.muted)
            }
        }
    }

    private var progress: CGFloat {
        let now = Date().timeIntervalSince1970 * 1000
        let rise = LogicEngine.shared.number("parseLocationLocalIso", [sunriseIso, utcOffset]) ?? 0
        let set = LogicEngine.shared.number("parseLocationLocalIso", [sunsetIso, utcOffset]) ?? 0
        if set <= rise { return 0 }
        if now <= rise { return 0 }
        if now >= set { return 1 }
        return CGFloat((now - rise) / (set - rise))
    }
}

