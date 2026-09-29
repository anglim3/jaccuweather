import ActivityKit
import Foundation

/// Starts, updates, and ends the current-place Live Activity from the app process.
/// `pushType` stays nil: push-to-start is not used.
enum WeatherLiveActivitySync {
    @MainActor
    static func startOrUpdate(
        placeID: String,
        placeName: String,
        temperatureF: Double?,
        conditionText: String,
        symbolName: String
    ) {
        let state = WeatherActivityAttributes.ContentState(
            placeName: placeName.isEmpty ? "Current location" : placeName,
            temperatureF: temperatureF,
            conditionText: conditionText.isEmpty ? "Unknown" : conditionText,
            symbolName: symbolName.isEmpty ? "cloud.fill" : symbolName
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(6 * 60 * 60)
        )
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        print("WeatherLiveActivity: activitiesEnabled=\(enabled)")

        let existing = Activity<WeatherActivityAttributes>.activities
        if let current = existing.first {
            Task { await current.update(content) }
            for extra in existing.dropFirst() {
                Task { await extra.end(nil, dismissalPolicy: .immediate) }
            }
            print("WeatherLiveActivity: updated")
            return
        }

        do {
            _ = try Activity.request(
                attributes: WeatherActivityAttributes(placeID: placeID),
                content: content,
                pushType: nil
            )
            print("WeatherLiveActivity: started")
        } catch {
            print("WeatherLiveActivity: start failed \(String(describing: error))")
        }
    }

    @MainActor
    static func end() {
        let existing = Activity<WeatherActivityAttributes>.activities
        guard !existing.isEmpty else { return }
        for activity in existing {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        print("WeatherLiveActivity: ended count=\(existing.count)")
    }
}
