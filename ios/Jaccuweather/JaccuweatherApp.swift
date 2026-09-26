import SwiftUI

enum LaunchArgs {
    static var tab: Int { value("tab").flatMap(Int.init) ?? 0 }
    static var hourly: String { value("hourly") ?? "conditions" }
    static var daily: String { value("daily") ?? "temp" }
    static var latitude: Double? { value("lat").flatMap(Double.init) }
    static var longitude: Double? { value("lon").flatMap(Double.init) }
    static var placeName: String? { value("name") }
    /// Simulator-only: drop `us_aqi` so the Air Quality card stays hidden.
    static var omitAqi: Bool { value("aqi") == "omit" }

    static func value(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-\(name)"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}

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
