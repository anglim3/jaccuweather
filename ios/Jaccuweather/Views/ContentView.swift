import SwiftUI

struct ContentView: View {
    @Environment(WeatherViewModel.self) private var model
    @State private var showSearch = false

    var body: some View {
        TabView {
            NavigationStack {
                CurrentConditionsView()
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Button {
                                showSearch = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass")
                                    Text(model.locationName)
                                        .lineLimit(1)
                                }
                            }
                            .accessibilityLabel("Change location")
                        }
                    }
                    .overlay { loadingOverlay }
            }
            .tabItem { Label("Now", systemImage: "sun.max") }

            NavigationStack {
                ForecastView()
                    .overlay { loadingOverlay }
            }
            .tabItem { Label("Forecast", systemImage: "calendar") }

            NavigationStack {
                HealthPollenView()
                    .overlay { loadingOverlay }
            }
            .tabItem { Label("Health", systemImage: "heart.fill") }

            NavigationStack {
                RadarView()
            }
            .tabItem { Label("Radar", systemImage: "map") }
        }
        .tint(JWTheme.accent)
        .task { await model.bootstrap() }
        .sheet(isPresented: $showSearch) {
            SearchSheet()
                .environment(model)
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if model.isLoading && model.forecast == nil {
            ProgressView("Fetching Open-Meteo…")
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

#Preview {
    ContentView()
        .environment(WeatherViewModel())
        .preferredColorScheme(.dark)
}
