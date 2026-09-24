import Foundation
import JavaScriptCore

/// Runs the website's DOM-free logic (ensemble averaging, icons, health, moon, pollen normalize).
final class LogicEngine {
    static let shared = LogicEngine()
    private let ctx = JSContext()!

    private init() {
        ctx.exceptionHandler = { _, error in
            print("Jaccuweather JS:", error as Any)
        }
        let candidates = [
            Bundle.main.url(forResource: "jaccuweather-logic", withExtension: "js", subdirectory: "Resources/Logic"),
            Bundle.main.url(forResource: "jaccuweather-logic", withExtension: "js", subdirectory: "Logic"),
            Bundle.main.url(forResource: "jaccuweather-logic", withExtension: "js")
        ]
        guard let url = candidates.compactMap({ $0 }).first,
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("Jaccuweather JS: logic bundle missing from app resources")
            return
        }
        ctx.evaluateScript(source)
    }

    private var logic: JSValue? {
        ctx.objectForKeyedSubscript("JaccuweatherLogic")
    }

    func invoke(_ name: String, _ args: [Any] = []) -> JSValue? {
        logic?.invokeMethod(name, withArguments: args)
    }

    func object(_ name: String, _ args: [Any] = []) -> Any? {
        guard let value = invoke(name, args), !value.isUndefined, !value.isNull else { return nil }
        return value.toObject()
    }

    func string(_ name: String, _ args: [Any] = []) -> String? {
        invoke(name, args)?.toString()
    }

    func number(_ name: String, _ args: [Any] = []) -> Double? {
        guard let value = invoke(name, args), value.isNumber else { return nil }
        return value.toDouble()
    }

    /// JSValue.toBool is a method on current SDKs (Xcode 26 / iOS 27); never read `.toBool` as a property.
    func bool(_ name: String, _ args: [Any] = []) -> Bool {
        guard let value = invoke(name, args), !value.isUndefined, !value.isNull else { return false }
        return value.toBool()
    }

    func normalizeEnsemble(_ raw: Any, latitude: Double, longitude: Double) -> JSONMap {
        JSONMap(object("normalizeEnsembleForNative", [raw, latitude, longitude]))
    }

    func pollenForecastDays(_ pollen: JSONMap) -> [JSONMap] {
        guard let value = invoke("buildPollenForecastDays", [pollen.raw]), !value.isUndefined, !value.isNull else {
            return []
        }
        return (value.toArray() as? [Any] ?? []).map { JSONMap($0) }
    }

    func weatherIconFile(code: Int?, isDay: Bool, precipProbability: Double? = nil) -> String {
        let args: [Any] = [code as Any, isDay, precipProbability as Any]
        return string("getWeatherIconFile", args) ?? (isDay ? "clear-day.svg" : "clear-night.svg")
    }

    func weatherDescription(_ code: Int?) -> String {
        string("getWeatherDescription", [code as Any]) ?? "Unknown"
    }

    func alertIconFile(_ event: String?) -> String {
        string("getAlertIconFile", [event as Any]) ?? "weather-alarm.svg"
    }

    func weatherSkyTheme(code: Int?, isDay: Bool) -> String {
        string("weatherSkyTheme", [code as Any, isDay]) ?? "cloudy"
    }

    func uvLabel(_ value: Double?) -> String {
        string("uvCategoryLabel", [value as Any]) ?? "Low"
    }
}
