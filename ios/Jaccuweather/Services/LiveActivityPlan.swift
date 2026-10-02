import Foundation

/// How the current-place Live Activity should change.
/// `placeID` is an activity attribute. Attributes are fixed when the activity
/// starts, so a different place has to end the old activity and start another.
enum LiveActivityPlan: Equatable {
    /// No activity is running.
    case start(placeID: String)
    /// Keep one activity with this place id, refresh its content, and end any others.
    case update(placeID: String)
    /// Every running activity belongs to another place. End them, then start one.
    case replace(placeID: String)
    /// There is no current weather, and an activity is still running.
    case end
    /// There is no current weather and no activity.
    case idle

    static func decide(existingPlaceIDs: [String], placeID: String?) -> LiveActivityPlan {
        let next = placeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if next.isEmpty {
            return existingPlaceIDs.isEmpty ? .idle : .end
        }
        if existingPlaceIDs.isEmpty {
            return .start(placeID: next)
        }
        if existingPlaceIDs.contains(next) {
            return .update(placeID: next)
        }
        return .replace(placeID: next)
    }
}
