import SwiftUI

@main
struct JaccuweatherApp: App {
    @State private var model = WeatherViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
    }
}
