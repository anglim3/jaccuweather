import Foundation
import JavaScriptCore

/// Runs the website's DOM-free logic (ensemble averaging, icons, health, moon, pollen normalize).
final class LogicEngine {
    static let shared = LogicEngine()
    private let ctx = JSContext()!
    /// JavaScriptCore contexts are single-threaded. Forecast normalize and pollen
    /// normalize run off the main actor while the Health and Now tabs call in.
    private let gate = NSLock()

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

    func object(_ name: String, _ args: [Any] = []) -> Any? {
        withContext { logic in
            guard let value = logic?.invokeMethod(name, withArguments: args), !value.isUndefined, !value.isNull else { return nil }
            return value.toObject()
        }
    }

    func string(_ name: String, _ args: [Any] = []) -> String? {
        withContext { logic in
            logic?.invokeMethod(name, withArguments: args)?.toString()
        }
    }

    func number(_ name: String, _ args: [Any] = []) -> Double? {
        withContext { logic in
            guard let value = logic?.invokeMethod(name, withArguments: args), value.isNumber else { return nil }
            return value.toDouble()
        }
    }

    func array(_ name: String, _ args: [Any] = []) -> [Any]? {
        withContext { logic in
            guard let value = logic?.invokeMethod(name, withArguments: args), !value.isUndefined, !value.isNull else { return nil }
            return value.toArray()
        }
    }

    /// JSValue.toBool is a method on current SDKs (Xcode 26 / iOS 27); never read `.toBool` as a property.
    func bool(_ name: String, _ args: [Any] = []) -> Bool {
        withContext { logic in
            guard let value = logic?.invokeMethod(name, withArguments: args), !value.isUndefined, !value.isNull else { return false }
            return value.toBool()
        }
    }

    private func withContext<T>(_ body: (JSValue?) -> T) -> T {
        gate.lock()
        defer { gate.unlock() }
        return body(logic)
    }

    func normalizeEnsemble(_ raw: Any, latitude: Double, longitude: Double) -> JSONMap {
        JSONMap(object("normalizeEnsembleForNative", [raw, latitude, longitude]))
    }

    func pollenForecastDays(_ pollen: JSONMap) -> [JSONMap] {
        let rows = array("buildPollenForecastDays", [pollen.raw]) ?? []
        return rows.map { JSONMap($0) }
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

    func uvLabel(_ value: Double?) -> String {
        string("uvCategoryLabel", [value as Any]) ?? "Low"
    }
}
