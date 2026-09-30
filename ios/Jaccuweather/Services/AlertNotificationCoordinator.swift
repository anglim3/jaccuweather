import Foundation
import UserNotifications

enum AlertNotificationPreference: String {
    case unset
    case on
    case off
}

enum AlertNotificationStore {
    private static let preferenceKey = "jaccuweather.alertNotifications.preference"
    private static let idsKey = "jaccuweather.alertNotifications.notifiedIDs"
    private static let maxIDs = 200

    static var preference: AlertNotificationPreference {
        get {
            let raw = UserDefaults.standard.string(forKey: preferenceKey) ?? ""
            return AlertNotificationPreference(rawValue: raw) ?? .unset
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: preferenceKey)
        }
    }

    static func notifiedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: idsKey) ?? [])
    }

    static func rememberNotified(_ ids: [String]) {
        var ordered = UserDefaults.standard.stringArray(forKey: idsKey) ?? []
        var known = Set(ordered)
        for id in ids where !id.isEmpty && known.insert(id).inserted {
            ordered.append(id)
        }
        if ordered.count > maxIDs {
            ordered.removeFirst(ordered.count - maxIDs)
        }
        UserDefaults.standard.set(ordered, forKey: idsKey)
    }
}

enum PrecipNotificationStore {
    private static let preferenceKey = "jaccuweather.precipNotifications.preference"
    private static let idsKey = "jaccuweather.precipNotifications.notifiedIDs"
    private static let postedKey = "jaccuweather.precipNotifications.posted"
    private static let maxIDs = 200

    static var preference: AlertNotificationPreference {
        get {
            let raw = UserDefaults.standard.string(forKey: preferenceKey) ?? ""
            return AlertNotificationPreference(rawValue: raw) ?? .unset
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: preferenceKey)
        }
    }

    static func notifiedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: idsKey) ?? [])
    }

    static func rememberNotified(_ ids: [String]) {
        var ordered = UserDefaults.standard.stringArray(forKey: idsKey) ?? []
        var known = Set(ordered)
        for id in ids where !id.isEmpty && known.insert(id).inserted {
            ordered.append(id)
        }
        if ordered.count > maxIDs {
            ordered.removeFirst(ordered.count - maxIDs)
        }
        UserDefaults.standard.set(ordered, forKey: idsKey)
    }

    static func posted() -> [PrecipPostedRecord] {
        guard let data = UserDefaults.standard.data(forKey: postedKey),
              let rows = try? JSONDecoder().decode([PrecipPostedRecord].self, from: data) else {
            return []
        }
        return rows
    }

    static func rememberPosted(_ record: PrecipPostedRecord) {
        var rows = posted().filter { $0.identifier != record.identifier }
        rows.append(record)
        if rows.count > 40 {
            rows.removeFirst(rows.count - 40)
        }
        savePosted(rows)
    }

    static func forgetPosted(_ identifiers: [String]) {
        let drop = Set(identifiers)
        guard !drop.isEmpty else { return }
        savePosted(posted().filter { !drop.contains($0.identifier) })
    }

    private static func savePosted(_ rows: [PrecipPostedRecord]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: postedKey)
    }
}

extension NWSAlertFeature {
    static let notificationIDKey = "nwsAlertID"

    func notificationUserInfo() -> [String: String] {
        var info = [Self.notificationIDKey: id]
        func put(_ key: String, _ value: String?) {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { return }
            info[key] = String(trimmed.prefix(2000))
        }
        put("event", properties.event)
        put("severity", properties.severity)
        put("urgency", properties.urgency)
        put("headline", properties.headline)
        put("description", properties.description)
        put("instruction", properties.instruction)
        put("ends", properties.ends)
        put("sender", properties.senderName)
        return info
    }

    init?(notificationUserInfo info: [AnyHashable: Any]) {
        func str(_ key: String) -> String? {
            guard let value = info[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let id = str(Self.notificationIDKey) else { return nil }
        self.init(properties: NWSAlertProperties(
            id: id,
            headline: str("headline"),
            event: str("event"),
            severity: str("severity"),
            urgency: str("urgency"),
            status: "Actual",
            description: str("description"),
            instruction: str("instruction"),
            ends: str("ends"),
            senderName: str("sender")
        ))
    }
}

enum AlertNotificationToggleResult {
    case on
    case off
    case denied
}

/// Local notifications only. No push capability and no remote registration.
@MainActor
final class AlertNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertNotificationCoordinator()

    weak var model: WeatherViewModel?
    private var pendingUserInfo: [AnyHashable: Any]?
    private var permissionTask: Task<Bool, Never>?
    private var postingIDs = Set<String>()
    private var postingPrecipIDs = Set<String>()

    private override init() {
        super.init()
    }

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func takePendingUserInfo() -> [AnyHashable: Any]? {
        defer { pendingUserInfo = nil }
        return pendingUserInfo
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func setPrecipEnabled(_ enabled: Bool) async -> AlertNotificationToggleResult {
        if !enabled {
            PrecipNotificationStore.preference = .off
            return .off
        }
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            PrecipNotificationStore.preference = .on
            return .on
        case .notDetermined:
            let granted = await requestPermission()
            PrecipNotificationStore.preference = granted ? .on : .off
            return granted ? .on : .denied
        case .denied:
            PrecipNotificationStore.preference = .off
            return .denied
        @unknown default:
            PrecipNotificationStore.preference = .off
            return .denied
        }
    }

    /// Posts one local notice when precipitation is about to start, and removes
    /// a notice whose hour has passed or whose start the forecast dropped.
    func handleFreshPrecip(
        _ notice: PrecipStartNotice?,
        placeName: String,
        placeKey: String,
        currentTime: String
    ) async {
        let allowPost = PrecipNotificationStore.preference == .on
        let activeIdentifier = allowPost ? notice?.identifier : nil
        let cancelIDs = PrecipNotificationCopy.identifiersToCancel(
            posted: PrecipNotificationStore.posted(),
            activeIdentifier: activeIdentifier,
            placeKey: placeKey,
            currentTime: currentTime
        )
        if !cancelIDs.isEmpty {
            let center = UNUserNotificationCenter.current()
            center.removeDeliveredNotifications(withIdentifiers: cancelIDs)
            center.removePendingNotificationRequests(withIdentifiers: cancelIDs)
            PrecipNotificationStore.forgetPosted(cancelIDs)
        }
        guard allowPost, let notice else { return }
        guard !PrecipNotificationStore.notifiedIDs().contains(notice.dedupeKey) else { return }
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            guard postingPrecipIDs.insert(notice.dedupeKey).inserted else { return }
            let posted = await postPrecip(notice, placeName: placeName)
            postingPrecipIDs.remove(notice.dedupeKey)
            if posted {
                PrecipNotificationStore.rememberNotified([notice.dedupeKey])
                PrecipNotificationStore.rememberPosted(PrecipPostedRecord(
                    identifier: notice.identifier,
                    placeKey: placeKey,
                    startTime: notice.startTime
                ))
            }
        default:
            break
        }
    }

    func setEnabled(_ enabled: Bool) async -> AlertNotificationToggleResult {
        if !enabled {
            AlertNotificationStore.preference = .off
            return .off
        }
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            AlertNotificationStore.preference = .on
            return .on
        case .notDetermined:
            let granted = await requestPermission()
            AlertNotificationStore.preference = granted ? .on : .off
            return granted ? .on : .denied
        case .denied:
            AlertNotificationStore.preference = .off
            return .denied
        @unknown default:
            AlertNotificationStore.preference = .off
            return .denied
        }
    }

    /// Posts for alert ids that are active now and not already in UserDefaults.
    func handleFreshAlerts(_ alerts: [NWSAlertFeature], placeName: String) async {
        let pending = freshAlerts(in: alerts)
        guard !pending.isEmpty else { return }
        switch AlertNotificationStore.preference {
        case .off:
            return
        case .on:
            await deliverIfAuthorized(pending, placeName: placeName, askWhenUnset: false)
        case .unset:
            await deliverIfAuthorized(pending, placeName: placeName, askWhenUnset: true)
        }
        model?.reloadAlertNotificationPreference()
    }

    #if DEBUG
    func postSample(placeName: String) async -> Bool {
        let sample = NWSAlertFeature(properties: NWSAlertProperties(
            id: "debug-sample-nws-alert",
            headline: "Sample alert for this place. This is not a live National Weather Service product.",
            event: "Wind Advisory",
            severity: "Moderate",
            urgency: "Expected",
            status: "Actual",
            description: "Debug preview of a local notification. No National Weather Service alert was delivered.",
            instruction: "No action is required.",
            ends: nil,
            senderName: "Debug preview"
        ))
        return await post(sample, placeName: placeName, identifier: "debug-sample-nws-alert")
    }

    func postSamplePrecip(placeName: String) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = PrecipNotificationCopy.title(kind: .rain)
        content.body = PrecipNotificationCopy.sampleBody(placeName: placeName)
        let place = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty { content.subtitle = place }
        content.sound = .default
        content.userInfo = PrecipNotificationCopy.userInfo(startTime: "sample")
        let request = UNNotificationRequest(
            identifier: PrecipNotificationCopy.sampleIdentifier,
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }
    #endif

    func open(_ info: [AnyHashable: Any]) {
        if PrecipNotificationCopy.isForecastRoute(info) {
            if let model {
                model.openForecastTab()
            } else {
                pendingUserInfo = info
            }
            return
        }
        if let model {
            model.openRoutedAlert(userInfo: info)
        } else {
            pendingUserInfo = info
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        await MainActor.run {
            if FreezeWarningCopy.isForecastRoute(info) {
                FreezeNotificationCoordinator.shared.openForecast()
            } else if WindGustNotificationCopy.isForecastRoute(info) {
                WindGustNotificationCoordinator.shared.openForecast()
            } else {
                AlertNotificationCoordinator.shared.open(info)
            }
        }
    }

    private func deliverIfAuthorized(
        _ alerts: [NWSAlertFeature],
        placeName: String,
        askWhenUnset: Bool
    ) async {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            if AlertNotificationStore.preference == .unset {
                AlertNotificationStore.preference = .on
            }
            await postAndRemember(alerts, placeName: placeName)
        case .notDetermined:
            guard askWhenUnset else { return }
            let granted = await requestPermission()
            AlertNotificationStore.preference = granted ? .on : .off
            if granted {
                await postAndRemember(alerts, placeName: placeName)
            }
        case .denied:
            if AlertNotificationStore.preference == .unset {
                AlertNotificationStore.preference = .off
            }
        @unknown default:
            break
        }
    }

    private func freshAlerts(in alerts: [NWSAlertFeature]) -> [NWSAlertFeature] {
        let ids = AlertNotificationCopy.idsToNotify(
            activeIDs: alerts.map(\.id),
            alreadyNotified: AlertNotificationStore.notifiedIDs()
        )
        let wanted = Set(ids)
        var ordered: [NWSAlertFeature] = []
        var seen = Set<String>()
        for alert in alerts where wanted.contains(alert.id) && seen.insert(alert.id).inserted {
            ordered.append(alert)
        }
        return ordered
    }

    private func postAndRemember(_ alerts: [NWSAlertFeature], placeName: String) async {
        for alert in alerts {
            let id = alert.id
            let already = AlertNotificationStore.notifiedIDs()
            guard !id.isEmpty, !already.contains(id), postingIDs.insert(id).inserted else { continue }
            let posted = await post(alert, placeName: placeName, identifier: "nws.\(id)")
            postingIDs.remove(id)
            if posted {
                AlertNotificationStore.rememberNotified([id])
            }
        }
    }

    private func postPrecip(_ notice: PrecipStartNotice, placeName: String) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = PrecipNotificationCopy.title(kind: notice.kind)
        content.body = PrecipNotificationCopy.body(placeName: placeName, time: notice.startTime, clock: notice.clock)
        let place = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty { content.subtitle = place }
        content.sound = .default
        content.userInfo = PrecipNotificationCopy.userInfo(startTime: notice.startTime)
        let request = UNNotificationRequest(identifier: notice.identifier, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    private func post(_ alert: NWSAlertFeature, placeName: String, identifier: String) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = AlertNotificationCopy.title(event: alert.properties.event, severity: alert.properties.severity)
        content.body = AlertNotificationCopy.body(headline: alert.properties.headline, placeName: placeName)
        let place = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty { content.subtitle = place }
        content.sound = .default
        content.userInfo = alert.notificationUserInfo()
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
