import SwiftUI

struct CurrentConditionsView: View {
    @Environment(WeatherViewModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let message = model.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if !model.alerts.isEmpty {
                    alertsCard
                }
                metrics
            }
            .padding(16)
        }
        .background(JWTheme.background.ignoresSafeArea())
        .navigationTitle("Now")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    model.requestDeviceLocation()
                } label: {
                    Image(systemName: "location.fill")
                }
                .accessibilityLabel("Use current location")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.favorites.toggle(model.currentPlace)
                } label: {
                    Image(systemName: model.favorites.contains(model.currentPlace) ? "star.fill" : "star")
                        .foregroundStyle(JWTheme.gold)
                }
                .accessibilityLabel("Toggle favorite")
            }
        }
        .refreshable { await model.refresh() }
    }

    private var header: some View {
        WeatherCard(title: model.locationName) {
            let current = model.forecast?.current
            let daily = model.forecast?.daily
            let today = daily?.todayIndex ?? 0
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tempText(current?.temperature2m))
                        .font(.system(size: 64, weight: .light, design: .rounded))
                    Text(WeatherCode.description(current?.weatherCode))
                        .font(.title3.weight(.medium))
                    if let high = daily?.temperature2mMax[safe: today], let low = daily?.temperature2mMin[safe: today],
                       let high, let low {
                        Text("H:\(Int(high.rounded()))°  L:\(Int(low.rounded()))°")
                            .foregroundStyle(JWTheme.muted)
                    }
                }
                Spacer()
                Image(systemName: WeatherCode.symbol(code: current?.weatherCode, isDay: current?.isDay != 0))
                    .font(.system(size: 56))
                    .foregroundStyle(JWTheme.gold)
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }

    private var metrics: some View {
        let current = model.forecast?.current
        return WeatherCard(title: "Conditions") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metric("Feels like", tempText(current?.apparentTemperature))
                metric("Humidity", current?.relativeHumidity2m.map { "\($0)%" } ?? "—")
                metric("Wind", current?.windSpeed10m.map { String(format: "%.0f mph", $0) } ?? "—")
                metric("UV", current?.uvIndex.map { String(format: "%.0f", $0) } ?? "—")
                metric("Pressure", current?.surfacePressure.map { String(format: "%.0f hPa", $0) } ?? "—")
                metric("Dew point", tempText(current?.dewPoint2m))
            }
        }
    }

    private var alertsCard: some View {
        WeatherCard(title: "NWS alerts") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(model.alerts.prefix(3))) { alert in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.properties.event ?? "Alert")
                            .font(.subheadline.weight(.semibold))
                        Text(alert.properties.headline ?? "")
                            .font(.caption)
                            .foregroundStyle(JWTheme.muted)
                    }
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(JWTheme.muted)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tempText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))°"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
