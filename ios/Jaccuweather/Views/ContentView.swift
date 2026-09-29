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
                    HorizonBackground()
                }
            }
            .tabItem { Label("Radar", systemImage: "map") }
            .tag(3)
        }
        .tint(theme.accent)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .task { await model.bootstrap() }
        .onAppear {
            if LaunchArgs.showSettings { showSettings = true }
            if LaunchArgs.showSearch { showSearch = true }
        }
        .onChange(of: tab) { _, new in
            loadedTabs.insert(new)
        }
        .onChange(of: model.routedAlert?.id) { _, id in
            guard id != nil else { return }
            tab = 0
            showSettings = false
            showSearch = false
        }
        .onChange(of: model.intentNowToken) { _, token in
            guard token != nil else { return }
            tab = 0
            showSettings = false
            showSearch = false
        }
        .onOpenURL { url in
            guard NowLink.opensNow(url) else { return }
            showNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NowLink.opened)) { _ in
            showNow()
        }
        .sheet(isPresented: $showSearch) {
            SearchSheet().environment(model)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(model)
        }
    }

    private func showNow() {
        tab = 0
        showSettings = false
        showSearch = false
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
                    HorizonBackground()
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
            Button { model.toggleAppearance() } label: {
                Image(systemName: model.appearance == .light ? "moon.fill" : "sun.max.fill")
            }
            .accessibilityLabel("Toggle dark/light mode")
            .accessibilityIdentifier("appearance-toggle")
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
            .jwGlass(.panel)
            .foregroundStyle(theme.text)
        } else if let message = model.blockingMessage {
            ProgressView(message)
                .padding(20)
                .jwGlass(.panel)
                .foregroundStyle(theme.text)
        }
    }
}
