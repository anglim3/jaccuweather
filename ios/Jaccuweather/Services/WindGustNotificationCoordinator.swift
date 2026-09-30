import Foundation
import UserNotifications

enum WindGustNotificationToggleResult {
    case on
    case off
    case denied
}

/// Local high-wind notices from the in-app hourly forecast. No push and no remote registration.
@MainActor
final class WindGustNotificationCoordinator {
    static let shared = WindGustNotificationCoordinator()

    weak var model: WeatherViewModel?
    private var pendingForecast = false
    private var permissionTask: Task<Bool, Never>?
    private var postingKeys = Set<String>()

    private init() {}

    func takePendingForecast() -> Bool {
        defer { pendingForecast = false }
        return pendingForecast
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func setEnabled(_ enabled: Bool) async -> WindGustNotificationToggleResult {
        if !enabled {
            WindGustNotificationStore.setOn(false)
            return .off
        }
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            WindGustNotificationStore.setOn(true)
            return .on
        case .notDetermined:
            let granted = await requestPermission()
            WindGustNotificationStore.setOn(granted)
            return granted ? .on : .denied
        case .denied:
            WindGustNotificationStore.setOn(false)
            return .denied
        @unknown default:
            WindGustNotificationStore.setOn(false)
            return .denied
        }
    }

    /// Posts at most one notice for the first damaging hour, and removes one that no longer applies.
    func handleForecast(
        hours: [WindHourSample],
        placeName: String,
        utcOffsetSeconds: Int,
        now: Date = Date()
    ) async {
        guard WindGustNotificationStore.isOn() else { return }
        let notice = WindGustNotificationCopy.upcoming(
            hours: hours,
            placeName: placeName,
            now: now,
            utcOffsetSeconds: utcOffsetSeconds
        )
        await prune(activeHour: notice?.hourKey, now: now, utcOffsetSeconds: utcOffsetSeconds)
        guard let notice else { return }
        guard WindGustNotificationCopy.shouldPost(key: notice.dedupeKey, alreadyPosted: WindGustNotificationStore.postedKeys()) else { return }
        guard await authorized() else { return }
        guard postingKeys.insert(notice.dedupeKey).inserted else { return }
        let posted = await post(
            title: WindGustNotificationCopy.title(usesGust: notice.usesGust),
            body: WindGustNotificationCopy.body(
                mph: notice.mph,
                usesGust: notice.usesGust,
                placeName: placeName,
                startClock: notice.startClock,
                endClock: notice.endClock
            ),
            identifier: notice.identifier,
            userInfo: WindGustNotificationCopy.userInfo(hourKey: notice.hourKey, dedupeKey: notice.dedupeKey)
        )
        postingKeys.remove(notice.dedupeKey)
        if posted {
            WindGustNotificationStore.remember(notice.dedupeKey)
        }
    }

    func openForecast() {
        if let model {
            model.openForecastTab()
        } else {
            pendingForecast = true
        }
        NotificationCenter.default.post(name: WindGustNotificationCopy.openedForecast, object: nil)
    }

    #if DEBUG
    func postSample(placeName: String) async -> Bool {
        let place = WindGustNotificationCopy.displayPlace(placeName)
        return await post(
            title: "Sample: Damaging gusts expected",
            body: "Sample for \(place). Gusts near 45 mph, 3:00 PM–4:00 PM. This is not a live forecast.",
            identifier: "debug-sample-wind-gust",
            userInfo: [
                WindGustNotificationCopy.routeKey: WindGustNotificationCopy.routeValue,
                "url": WindGustNotificationCopy.forecastURL.absoluteString,
                WindGustNotificationCopy.sampleKey: "1"
            ]
        )
    }
    #endif

    private func authorized() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private func prune(activeHour: String?, now: Date, utcOffsetSeconds: Int) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let pending = await center.pendingNotificationRequests()
        var identifiers: [String] = []
        func consider(_ request: UNNotificationRequest) {
            let info = request.content.userInfo
            guard WindGustNotificationCopy.ownsNotice(info), !WindGustNotificationCopy.isSample(info) else { return }
            let hour = info[WindGustNotificationCopy.hourKeyName] as? String ?? ""
            let remove = hour.isEmpty || WindGustNotificationCopy.shouldRemoveNotice(
                noticeHour: hour,
                now: now,
                utcOffsetSeconds: utcOffsetSeconds,
                activeHour: activeHour
            )
            if remove { identifiers.append(request.identifier) }
        }
        delivered.forEach { consider($0.request) }
        pending.forEach(consider)
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func post(
        title: String,
        body: String,
        identifier: String,
        userInfo: [String: String]
    ) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    private func requestPermission() async -> Bool {
        if let permissionTask {
            return await permissionTask.value
        }
        let task = Task { () -> Bool in
            do {
                return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        }
        permissionTask = task
        let granted = await task.value
        permissionTask = nil
        return granted
    }
}
