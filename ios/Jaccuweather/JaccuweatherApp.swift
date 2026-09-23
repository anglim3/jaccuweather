import SwiftUI

@main
struct JaccuweatherApp: App {
    @State private var model = WeatherViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await model.handleBecameActive() }
                    }
                }
        }
    }
}
