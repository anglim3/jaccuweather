import SwiftUI

struct ContentView: View {
    @Environment(WeatherViewModel.self) private var model
    @State private var showSearch = false

    var body: some View {
        TabView {
            NavigationStack {
                CurrentConditionsView()
                    .toolbar { locationToolbar }
                    .overlay { loadingOverlay }
            }
            .tabItem { Label("Now", systemImage: "sun.max") }

            NavigationStack {
                ForecastView()
                    .toolbar { locationToolbar }
                    .overlay { loadingOverlay }
            }
            .tabItem { Label("Forecast", systemImage: "calendar") }

            NavigationStack {
                HealthPollenView()
                    .toolbar { locationToolbar }
                    .overlay { loadingOverlay }
            }
            .tabItem { Label("Health", systemImage: "heart.fill") }

            NavigationStack {
                RadarView()
                    .toolbar { locationToolbar }
            }
            .tabItem { Label("Radar", systemImage: "map") }
        }
        .tint(JWTheme.accent)
        .task { await model.bootstrap() }
        .sheet(isPresented: $showSearch) {
            SearchSheet().environment(model)
        }
    }

    @ToolbarContentBuilder
    private var locationToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button { showSearch = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text(model.locationName).lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if model.isLoading && model.weather == nil {
            ProgressView("Fetching ensemble forecast…")
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
