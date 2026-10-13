import SwiftUI

enum LaunchArgs {
    static var tab: Int { value("tab").flatMap(Int.init) ?? 0 }
    static var hourly: String { value("hourly") ?? "conditions" }
    static var daily: String { value("daily") ?? "temp" }
    static var anchor: String? { value("anchor") }
    static var latitude: Double? { value("lat").flatMap(Double.init) }
    static var longitude: Double? { value("lon").flatMap(Double.init) }
    static var placeName: String? { value("name") }
    static var showSettings: Bool { value("settings") == "1" }
    static var showSearch: Bool { value("search") == "1" }
    #if DEBUG
    static var alertSample: Bool { value("alertSample") == "1" }
    static var precipSample: Bool { value("precipSample") == "1" }
    static var freezeSample: Bool { value("freezeSample") == "1" }
    static var windSample: Bool { value("windSample") == "1" }
    /// Drop `us_aqi` after fetch so the Air Quality card stays hidden.
    static var omitAqi: Bool { value("aqi") == "omit" }
    #else
    static var alertSample: Bool { false }
    static var precipSample: Bool { false }
    static var freezeSample: Bool { false }
    static var windSample: Bool { false }
    static var omitAqi: Bool { false }
    #endif

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

    init() {
        NowLink.startObserving()
        AlertNotificationCoordinator.shared.install()
        WatchSessionBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                // The site toggle is separate from the system appearance.
                // Dark chrome keeps glass type white on the navy field and on weather skies.
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await model.handleBecameActive() }
                    }
                }
        }
        .handlesExternalEvents(matching: ["*"])
    }
}
