import ActivityKit
import Foundation

/// Current-place reading shown on the Lock Screen and in the Dynamic Island.
/// Compiled into the app and the widget extension. The app fills it from the
/// in-process forecast. No push token and no App Group.
struct WeatherActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var placeName: String
        var temperatureF: Double?
        var conditionText: String
        var symbolName: String
    }

    /// Stable id for the place this activity was started for.
    var placeID: String
}

enum WeatherActivityText {
    static func degrees(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))°"
    }

    static func spoken(_ state: WeatherActivityAttributes.ContentState) -> String {
        let place = state.placeName.isEmpty ? "Current location" : state.placeName
        let condition = state.conditionText.isEmpty ? "Unknown conditions" : state.conditionText
        return "\(place), \(degrees(state.temperatureF)), \(condition)"
    }
}
