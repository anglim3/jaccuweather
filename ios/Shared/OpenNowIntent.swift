import AppIntents

/// Opens the Now tab. Compiled into the app and the widget extension so a
/// Control Center tap can run in the foreground app.
struct OpenNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Jaccuweather"
    static var description = IntentDescription("Opens the Now tab for the current place.")
    static var openAppWhenRun = true
    static var isDiscoverable = false
    static var persistentIdentifier = "cloud.janglim.jaccuweather.OpenNowIntent"

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        .foreground(.immediate)
    }

    func perform() async throws -> some IntentResult {
        NowLink.postOpen()
        return .result()
    }
}
