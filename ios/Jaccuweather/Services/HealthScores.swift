import Foundation

/// Ports of `calculateSinusRisk` / `calculateAllergyRisk` / labels in public/app.js.
enum HealthScores {
    struct Risk {
        let score: Int?
        let label: String
        let detail: String
    }

    /// 0–4, clipped. Pressure drop dominates; damp or swingy days add at most 1.
    static func sinusRisk(pressureChangeInHg: Double, humidity: Double, precipitationInches: Double, tempSwingF: Double) -> Risk {
        var risk = 0
        if pressureChangeInHg < -0.25 {
            risk += 3
        } else if pressureChangeInHg < -0.10 {
            risk += 2
        }
        let isDamp = humidity > 70 || precipitationInches > 0.1
        let isSwingy = tempSwingF > 20
        if isDamp || isSwingy { risk += 1 }
        risk = min(4, max(0, risk))
        var drivers: [String] = []
        if pressureChangeInHg < -0.25 { drivers.append("Falling fast") }
        else if pressureChangeInHg < -0.10 { drivers.append("Falling pressure") }
        if precipitationInches > 0.1 { drivers.append("Rain") }
        else if humidity > 70 { drivers.append("Humid") }
        else if tempSwingF > 20 { drivers.append("Large temp swing") }
        if drivers.isEmpty { drivers.append("Steady pressure") }
        return Risk(score: risk, label: simpleLabel(risk), detail: drivers.prefix(2).joined(separator: " · "))
    }

    /// Website: allergy score is pollen-driven; missing pollen → no data (not zero).
    static func allergyRisk(pollen: PollenSnapshot?) -> Risk {
        guard let pollen, pollen.hasAnyPollen, let maxPollen = pollen.maxPollen else {
            return Risk(score: nil, label: "No data", detail: "Pollen unavailable")
        }
        // Bands match public/app.js calculateAllergyRisk (≤20 Low, ≤80 Elevated, else High).
        let score: Int
        if maxPollen <= 20 { score = 1 }
        else if maxPollen <= 80 { score = 2 }
        else { score = 3 }
        return Risk(score: score, label: simpleLabel(score), detail: "Source \(pollen.source)")
    }

    static func simpleLabel(_ score: Int?) -> String {
        guard let score else { return "No data" }
        if score <= 1 { return "Low" }
        if score <= 2 { return "Elevated" }
        return "High"
    }

    static func aqiCategory(_ usAqi: Double) -> String {
        switch usAqi {
        case ...50: return "Good"
        case ...100: return "Moderate"
        case ...150: return "Unhealthy for sensitive groups"
        case ...200: return "Unhealthy"
        case ...300: return "Very unhealthy"
        default: return "Hazardous"
        }
    }
}
