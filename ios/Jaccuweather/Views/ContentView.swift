import SwiftUI

struct ContentView: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(JWAppearance.storageKey) private var appearance = JWAppearance.dark
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var tab = LaunchArgs.tab

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                CurrentConditionsView()
                    .toolbar { locationToolbar }
                    .overlay { loadingOverlay }
            }
            .tabItem { Label("Now", systemImage: "sun.max") }
            .tag(0)

            NavigationStack {
                ForecastView()
                    .toolbar { locationToolbar }
                    .overlay { loadingOverlay }
            }
            .tabItem { Label("Forecast", systemImage: "calendar") }
            .tag(1)

            NavigationStack {
                HealthPollenView()
                    .toolbar { locationToolbar }
                    .overlay { loadingOverlay }
            }
            .tabItem { Label("Health", systemImage: "heart.fill") }
            .tag(2)

            NavigationStack {
                RadarView()
                    .toolbar { locationToolbar }
            }
            .tabItem { Label("Radar", systemImage: "map") }
            .tag(3)
        }
        .tint(theme.accent)
        .task { await model.bootstrap() }
        .sheet(isPresented: $showSearch) {
            SearchSheet().environment(model)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(model)
        }
    }

    @ToolbarContentBuilder
    private var locationToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button { showSearch = true } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Search")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                appearance = appearance == JWAppearance.light ? JWAppearance.dark : JWAppearance.light
            } label: {
                Image(systemName: appearance == JWAppearance.light ? "moon.fill" : "sun.max.fill")
            }
            .accessibilityLabel(appearance == JWAppearance.light ? "Switch to dark appearance" : "Switch to light appearance")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
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
