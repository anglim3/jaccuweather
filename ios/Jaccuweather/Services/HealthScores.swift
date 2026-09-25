import Foundation

struct CachedHealth: Equatable {
    var sinusLabel: String
    var sinusDetail: String
    var allergyLabel: String
    var allergyDetail: String
    var niceLine: String

    static func make(weather: WeatherBundle, pollen: JSONMap?) -> CachedHealth {
        let sinus = HealthScores.sinus(from: weather)
        let allergy = HealthScores.allergy(pollen: pollen, weather: weather)
        let nice = HealthScores.niceWeather(from: weather)
        let niceLine = nice.score.map { "\($0)/10 \(nice.label)" } ?? "—"
        return CachedHealth(
            sinusLabel: sinus.label,
            sinusDetail: sinus.detail,
            allergyLabel: allergy.label,
            allergyDetail: allergy.detail,
            niceLine: niceLine
        )
    }
}

enum HealthScores {
    static func sinus(from weather: WeatherBundle) -> (label: String, detail: String, score: Int?) {
        let daily = weather.daily
        let today = weather.todayIndex
        let todayStr = daily.strings("time")[safe: today]
        let yesterdayStr = daily.strings("time")[safe: today - 1]
        let todayAvg = LogicEngine.shared.object("calculateDailyAveragesForDateString", [weather.hourly.raw, todayStr as Any])
        let yesterdayAvg = LogicEngine.shared.object("calculateDailyAveragesForDateString", [weather.hourly.raw, yesterdayStr as Any])
        let todayMap = JSONMap(todayAvg)
        let yMap = JSONMap(yesterdayAvg)
        let pressureChange = (todayMap.number("avgPressureInhg") ?? 0) - (yMap.number("avgPressureInhg") ?? todayMap.number("avgPressureInhg") ?? 0)
        let humidity = todayMap.number("avgHumidity") ?? weather.current.number("relative_humidity_2m") ?? 0
        let precip = todayMap.number("precipSum") ?? 0
        let high = daily.numbers("temperature_2m_max")[safe: today] ?? nil
        let low = daily.numbers("temperature_2m_min")[safe: today] ?? nil
        let swing = (high ?? 0) - (low ?? 0)
        let score = LogicEngine.shared.number("calculateSinusRisk", [pressureChange, humidity, precip, swing]).map { Int($0) }
        let label = JSONMap(LogicEngine.shared.object("getSimpleRiskLabel", [score as Any])).string("label") ?? "No data"
        let drivers = LogicEngine.shared.invoke("getSinusDrivers", [pressureChange, humidity, precip, swing])?.toArray() as? [String]
        return (label, (drivers ?? []).prefix(2).joined(separator: " · "), score)
    }

    static func allergy(pollen: JSONMap?, weather: WeatherBundle) -> (label: String, detail: String, score: Int?) {
        let todayStr = weather.daily.strings("time")[safe: weather.todayIndex]
        let todayAvg = JSONMap(LogicEngine.shared.object("calculateDailyAveragesForDateString", [weather.hourly.raw, todayStr as Any]))
        let scoreVal = LogicEngine.shared.invoke("calculateAllergyRisk", [
            todayAvg.number("windMax") as Any,
            todayAvg.number("precipSum") as Any,
            pollen?.raw as Any
        ])
        let score = scoreVal?.isNumber == true ? Int(scoreVal!.toDouble()) : nil
        let label = JSONMap(LogicEngine.shared.object("getSimpleRiskLabel", [score as Any])).string("label") ?? "No data"
        let drivers = LogicEngine.shared.invoke("getAllergyDrivers", [
            pollen?.raw as Any,
            todayAvg.number("windMax") as Any,
            todayAvg.number("precipSum") as Any
        ])?.toArray() as? [String]
        return (label, (drivers ?? []).prefix(2).joined(separator: " · "), score)
    }

    static func niceWeather(from weather: WeatherBundle) -> (score: Int?, label: String, factors: [JSONMap]) {
        let today = weather.todayIndex
        let todayStr = weather.daily.strings("time")[safe: today]
        let todayAvg = LogicEngine.shared.object("calculateDailyAveragesForDateString", [weather.hourly.raw, todayStr as Any])
        guard let breakdownAny = LogicEngine.shared.object("getNiceWeatherBreakdown", [weather.root.raw, todayAvg as Any, today]) else {
            return (nil, "Unavailable", [])
        }
        let breakdown = JSONMap(breakdownAny)
        let score = breakdown.int("score")
        let label = JSONMap(LogicEngine.shared.object("getNiceWeatherLabel", [score as Any])).string("label") ?? "—"
        return (score, label, breakdown.maps("factors"))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
