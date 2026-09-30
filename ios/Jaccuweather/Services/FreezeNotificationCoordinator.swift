import Foundation
import UserNotifications

enum FreezeNotificationToggleResult {
    case on
    case off
    case denied
}

/// Local freeze notices from the in-app daily forecast. No push and no remote registration.
@MainActor
final class FreezeNotificationCoordinator {
    static let shared = FreezeNotificationCoordinator()

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

    func setEnabled(_ enabled: Bool) async -> FreezeNotificationToggleResult {
        if !enabled {
            FreezeNotificationStore.setOn(false)
            return .off
        }
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            FreezeNotificationStore.setOn(true)
            return .on
        case .notDetermined:
            let granted = await requestPermission()
            FreezeNotificationStore.setOn(granted)
            return granted ? .on : .denied
        case .denied:
            FreezeNotificationStore.setOn(false)
            return .denied
        @unknown default:
            FreezeNotificationStore.setOn(false)
            return .denied
        }
    }

    /// Posts at most one notice for the current overnight, and removes one that no longer applies.
    func handleForecast(
        days: [String],
        lows: [Double?],
        placeName: String,
        utcOffsetSeconds: Int,
        now: Date = Date()
    ) async {
        guard FreezeNotificationStore.isOn() else { return }
        let night = FreezeWarningCopy.nextOvernight(
            days: days,
            lows: lows,
            now: now,
            utcOffsetSeconds: utcOffsetSeconds
        )
        await prune(activeDay: night?.day, activeLowF: night?.lowF, now: now, utcOffsetSeconds: utcOffsetSeconds)
        guard let night, FreezeWarningCopy.title(lowF: night.lowF) != nil else { return }
        let key = FreezeWarningCopy.dedupeKey(placeName: placeName, day: night.day)
        guard FreezeWarningCopy.shouldPost(key: key, alreadyPosted: FreezeNotificationStore.postedKeys()) else { return }
        guard await authorized() else { return }
        guard postingKeys.insert(key).inserted else { return }
        let posted = await post(
            title: FreezeWarningCopy.title(lowF: night.lowF) ?? "Freeze warning tonight",
            body: FreezeWarningCopy.body(lowF: night.lowF, placeName: placeName),
            identifier: FreezeWarningCopy.notificationIdentifier(for: key),
            userInfo: [
                FreezeWarningCopy.routeKey: FreezeWarningCopy.routeValue,
                "url": FreezeWarningCopy.forecastURL.absoluteString,
                FreezeWarningCopy.dayKey: night.day,
                FreezeWarningCopy.dedupeKeyName: key
            ]
        )
        postingKeys.remove(key)
        if posted {
            FreezeNotificationStore.remember(key)
        }
    }

    func openForecast() {
        if let model {
            model.openForecastTab()
        } else {
            pendingForecast = true
        }
        NotificationCenter.default.post(name: FreezeWarningCopy.openedForecast, object: nil)
    }

    #if DEBUG
    func postSample(placeName: String) async -> Bool {
        let place = FreezeWarningCopy.displayPlace(placeName)
        return await post(
            title: "Sample: Freeze warning tonight",
            body: "Low near 29° in \(place). This is not a live forecast.",
            identifier: "debug-sample-freeze-warning",
            userInfo: [
                FreezeWarningCopy.routeKey: FreezeWarningCopy.routeValue,
                "url": FreezeWarningCopy.forecastURL.absoluteString,
                FreezeWarningCopy.sampleKey: "1"
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

    private func prune(activeDay: String?, activeLowF: Double?, now: Date, utcOffsetSeconds: Int) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let pending = await center.pendingNotificationRequests()
        var identifiers: [String] = []
        func consider(_ request: UNNotificationRequest) {
            let info = request.content.userInfo
            guard FreezeWarningCopy.isForecastRoute(info), !FreezeWarningCopy.isSample(info) else { return }
            let day = info[FreezeWarningCopy.dayKey] as? String ?? ""
            let remove = day.isEmpty || FreezeWarningCopy.shouldRemoveNotice(
                noticeDay: day,
                now: now,
                utcOffsetSeconds: utcOffsetSeconds,
                activeDay: activeDay,
                activeLowF: activeLowF
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
