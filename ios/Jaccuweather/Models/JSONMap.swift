import Foundation

struct JSONMap {
    let raw: [String: Any]

    init(_ any: Any?) {
        if let dict = any as? [String: Any] {
            raw = dict
        } else if let dict = any as? NSDictionary {
            var mapped: [String: Any] = [:]
            for (key, value) in dict {
                if let key = key as? String { mapped[key] = value }
            }
            raw = mapped
        } else {
            raw = [:]
        }
    }

    func map(_ key: String) -> JSONMap { JSONMap(raw[key]) }

    func any(_ key: String) -> Any? { raw[key] }

    func string(_ key: String) -> String? { raw[key] as? String }

    func bool(_ key: String) -> Bool {
        if let b = raw[key] as? Bool { return b }
        if let n = number(key) { return n != 0 }
        return false
    }

    func number(_ key: String) -> Double? {
        Self.toDouble(raw[key])
    }

    func int(_ key: String) -> Int? {
        guard let n = number(key) else { return nil }
        return Int(n.rounded())
    }

    func strings(_ key: String) -> [String] {
        (raw[key] as? [Any])?.compactMap { $0 as? String } ?? []
    }

    func numbers(_ key: String) -> [Double?] {
        guard let arr = raw[key] as? [Any] else { return [] }
        return arr.map(Self.toDouble)
    }

    func maps(_ key: String) -> [JSONMap] {
        (raw[key] as? [Any])?.map { JSONMap($0) } ?? []
    }

    static func toDouble(_ value: Any?) -> Double? {
        if value == nil || value is NSNull { return nil }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}

struct WeatherBundle {
    let root: JSONMap
    var current: JSONMap { root.map("current") }
    var hourly: JSONMap { root.map("hourly") }
    var daily: JSONMap { root.map("daily") }
    var latitude: Double { root.number("latitude") ?? 0 }
    var longitude: Double { root.number("longitude") ?? 0 }
    var elevation: Double? { root.number("elevation") }
    var timezone: String? { root.string("timezone") }
    var utcOffset: Int { root.int("utc_offset_seconds") ?? 0 }

    var todayIndex: Int {
        let times = daily.strings("time")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: utcOffset)
        let today = formatter.string(from: Date())
        if let idx = times.firstIndex(of: today) { return idx }
        return min(2, max(0, times.count - 1))
    }
}
