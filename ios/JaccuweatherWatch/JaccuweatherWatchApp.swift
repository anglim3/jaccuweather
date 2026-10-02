import SwiftUI

@main
struct JaccuweatherWatchApp: App {
    @State private var model = WatchWeatherModel()

    var body: some Scene {
        WindowGroup {
            WatchGlanceView(model: model)
        }
    }
}
