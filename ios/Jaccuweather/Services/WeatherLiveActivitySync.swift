import ActivityKit
import Foundation

/// Starts, updates, and ends the current-place Live Activity from the app process.
/// `pushType` stays nil: push-to-start is not used.
/// A place change ends the previous activity before starting the next one.
/// Attributes cannot be edited, and a second activity is not left running.
enum WeatherLiveActivitySync {
    @MainActor
    private static var generation = 0

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
        generation += 1
        let token = generation
        let activities = Activity<WeatherActivityAttributes>.activities
        switch LiveActivityPlan.decide(existingPlaceIDs: activities.map(\.attributes.placeID), placeID: placeID) {
        case .idle:
            return
        case .end:
            endActivities(activities)
        case .start(let id):
            request(placeID: id, content: content, token: token)
        case .update(let id):
            keepMatching(placeID: id, content: content, activities: activities, token: token)
        case .replace(let id):
            Task { await replace(placeID: id, content: content, token: token) }
        }
    }

    /// Ends every current-place activity. Later start requests from an older refresh are ignored.
    @MainActor
    static func end() {
        generation += 1
        endActivities(Activity<WeatherActivityAttributes>.activities)
    }

    @MainActor
    private static func endActivities(_ activities: [Activity<WeatherActivityAttributes>]) {
        for activity in activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    @MainActor
    private static func keepMatching(
        placeID: String,
        content: ActivityContent<WeatherActivityAttributes.ContentState>,
        activities: [Activity<WeatherActivityAttributes>],
        token: Int
    ) {
        guard let current = activities.first(where: { $0.attributes.placeID == placeID }) else { return }
        let extras = activities.filter { $0.id != current.id }
        Task { @MainActor in
            guard token == generation else { return }
            await current.update(content)
            guard token == generation else { return }
            for extra in extras {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// End activities that still carry another place, then start one for `placeID`.
    /// A newer refresh supersedes this handoff.
    @MainActor
    private static func replace(
        placeID: String,
        content: ActivityContent<WeatherActivityAttributes.ContentState>,
        token: Int
    ) async {
        let stale = Activity<WeatherActivityAttributes>.activities.filter { $0.attributes.placeID != placeID }
        for activity in stale {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard token == generation else { return }
        if let current = Activity<WeatherActivityAttributes>.activities.first(where: { $0.attributes.placeID == placeID }) {
            await current.update(content)
            guard token == generation else { return }
            let extras = Activity<WeatherActivityAttributes>.activities.filter { $0.id != current.id }
            for extra in extras {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
            return
        }
        request(placeID: placeID, content: content, token: token)
    }

    @MainActor
    private static func request(
        placeID: String,
        content: ActivityContent<WeatherActivityAttributes.ContentState>,
        token: Int
    ) {
        guard token == generation else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity.request(
            attributes: WeatherActivityAttributes(placeID: placeID),
            content: content,
            pushType: nil
        )
    }
}
