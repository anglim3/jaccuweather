import SwiftUI

struct ContentView: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var tab = LaunchArgs.tab
    @State private var loadedTabs: Set<Int> = [LaunchArgs.tab]

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        TabView(selection: $tab) {
            tabStack(0) { CurrentConditionsView() }
                .tabItem { Label("Now", systemImage: "sun.max") }
                .tag(0)

            tabStack(1) { ForecastView() }
                .tabItem { Label("Forecast", systemImage: "calendar") }
                .tag(1)

            tabStack(2) { HealthPollenView() }
                .tabItem { Label("Health", systemImage: "heart.fill") }
                .tag(2)

            tabStack(3) {
                if model.hasResolvedPlace {
                    RadarView(isActive: tab == 3)
                } else {
                    theme.background
                }
            }
            .tabItem { Label("Radar", systemImage: "map") }
            .tag(3)
        }
        .tint(theme.accent)
        .task { await model.bootstrap() }
        .onChange(of: tab) { _, new in
            loadedTabs.insert(new)
        }
        .sheet(isPresented: $showSearch) {
            SearchSheet().environment(model)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(model)
        }
    }

    private func tabIsLoaded(_ tag: Int) -> Bool {
        tab == tag || loadedTabs.contains(tag)
    }

    private func tabStack<Content: View>(_ tag: Int, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            Group {
                if tabIsLoaded(tag) {
                    content()
                } else {
                    theme.background
                }
            }
            .toolbar { locationToolbar }
            .overlay { loadingOverlay }
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
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if model.showsPlacePrompt && model.weather == nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Location is off")
                    .font(.headline)
                Text("Allow location to see weather where you are, or search for a city.")
                    .font(.subheadline)
                    .foregroundStyle(theme.muted)
                Button("Allow Location") { model.requestDeviceLocation() }
                    .buttonStyle(.borderedProminent)
                Button("Search") { showSearch = true }
                    .buttonStyle(.bordered)
            }
            .padding(20)
            .frame(maxWidth: 360, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.cardStroke, lineWidth: 1)
            )
            .foregroundStyle(theme.text)
        } else if let message = model.blockingMessage {
            ProgressView(message)
                .padding(20)
                .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
                .foregroundStyle(theme.text)
        }
    }
}
