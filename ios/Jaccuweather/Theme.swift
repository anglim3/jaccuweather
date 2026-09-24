import SwiftUI

/// Glass colors for one appearance. Dark matches the site’s static deep blue.
/// Light keeps pale glass cards (dark ink) so text stays readable on the
/// weather-reactive sky painted behind them.
struct JWPalette {
    let background: Color
    let card: Color
    let cardStroke: Color
    let accent: Color
    let muted: Color
    let gold: Color
    let text: Color
    let tile: Color
    let grid: Color
    let cloudLow: Color
    let cloudMid: Color
    let cloudHigh: Color
    let sunStroke: Color
    let moon: Color

    static let dark = JWPalette(
        background: Color(red: 13 / 255, green: 33 / 255, blue: 55 / 255),
        card: Color.white.opacity(0.08),
        cardStroke: Color.white.opacity(0.12),
        accent: Color(red: 125 / 255, green: 211 / 255, blue: 252 / 255),
        muted: Color.white.opacity(0.65),
        gold: Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255),
        text: .white,
        tile: Color.white.opacity(0.04),
        grid: Color.white.opacity(0.08),
        cloudLow: Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255),
        cloudMid: Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255),
        cloudHigh: Color(red: 226 / 255, green: 232 / 255, blue: 240 / 255),
        sunStroke: Color.white.opacity(0.22),
        moon: Color(red: 226 / 255, green: 232 / 255, blue: 240 / 255)
    )

    static let light = JWPalette(
        background: Color(red: 226 / 255, green: 236 / 255, blue: 245 / 255),
        card: Color.white.opacity(0.88),
        cardStroke: Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.10),
        accent: Color(red: 3 / 255, green: 105 / 255, blue: 161 / 255),
        muted: Color(red: 51 / 255, green: 65 / 255, blue: 85 / 255).opacity(0.78),
        gold: Color(red: 161 / 255, green: 98 / 255, blue: 7 / 255),
        text: Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255),
        tile: Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.05),
        grid: Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.10),
        cloudLow: Color(red: 3 / 255, green: 105 / 255, blue: 161 / 255),
        cloudMid: Color(red: 161 / 255, green: 98 / 255, blue: 7 / 255),
        cloudHigh: Color(red: 71 / 255, green: 85 / 255, blue: 105 / 255),
        sunStroke: Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.18),
        moon: Color(red: 71 / 255, green: 85 / 255, blue: 105 / 255)
    )

    static func forScheme(_ scheme: ColorScheme) -> JWPalette {
        scheme == .light ? .light : .dark
    }
}

enum JWAppearance {
    static let storageKey = "jaccuweather-theme"
    static let dark = "dark"
    static let light = "light"
}

/// Light-mode page background. Class names match `setTheme()` / `.bg-layer.*` on the website.
struct SkyBackdrop: View {
    var name: String

    var body: some View {
        ZStack {
            LinearGradient(colors: stops.linear, startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [stops.glow, .clear],
                center: stops.glowCenter,
                startRadius: 0,
                endRadius: 460
            )
            if let second = stops.second {
                RadialGradient(
                    colors: [second.color, .clear],
                    center: second.center,
                    startRadius: 0,
                    endRadius: 380
                )
            }
        }
        .ignoresSafeArea()
    }

    private var stops: SkyStops {
        switch name {
        case "sunny":
            return SkyStops(
                linear: [rgb(59, 130, 246), rgb(14, 165, 233), rgb(3, 105, 161)],
                glow: rgb(251, 191, 36).opacity(0.45),
                glowCenter: UnitPoint(x: 0.70, y: 0.0),
                second: SkyGlow(color: rgb(56, 189, 248).opacity(0.25), center: UnitPoint(x: 0.10, y: 0.80))
            )
        case "clear-night":
            return SkyStops(
                linear: [rgb(15, 23, 42), rgb(30, 27, 75), rgb(12, 10, 29)],
                glow: Color.white.opacity(0.15),
                glowCenter: UnitPoint(x: 0.80, y: 0.15),
                second: SkyGlow(color: rgb(99, 102, 241).opacity(0.35), center: UnitPoint(x: 0.20, y: 0.70))
            )
        case "rainy":
            return SkyStops(
                linear: [rgb(30, 58, 95), rgb(15, 39, 68), rgb(12, 25, 41)],
                glow: rgb(100, 116, 139).opacity(0.40),
                glowCenter: UnitPoint(x: 0.50, y: 0.0),
                second: nil
            )
        case "storm":
            return SkyStops(
                linear: [rgb(30, 27, 75), rgb(15, 23, 42), rgb(2, 6, 23)],
                glow: rgb(139, 92, 246).opacity(0.30),
                glowCenter: UnitPoint(x: 0.70, y: 0.30),
                second: nil
            )
        case "snow":
            return SkyStops(
                linear: [rgb(148, 163, 184), rgb(100, 116, 139), rgb(51, 65, 85)],
                glow: rgb(226, 232, 240).opacity(0.40),
                glowCenter: UnitPoint(x: 0.40, y: 0.10),
                second: nil
            )
        case "fog":
            return SkyStops(
                linear: [rgb(100, 116, 139), rgb(71, 85, 105), rgb(51, 65, 85)],
                glow: rgb(203, 213, 225).opacity(0.25),
                glowCenter: UnitPoint(x: 0.50, y: 0.40),
                second: nil
            )
        default:
            return SkyStops(
                linear: [rgb(71, 85, 105), rgb(51, 65, 85), rgb(30, 41, 59)],
                glow: rgb(148, 163, 184).opacity(0.35),
                glowCenter: UnitPoint(x: 0.30, y: 0.20),
                second: nil
            )
        }
    }

    private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }
}

private struct SkyGlow {
    let color: Color
    let center: UnitPoint
}

private struct SkyStops {
    let linear: [Color]
    let glow: Color
    let glowCenter: UnitPoint
    let second: SkyGlow?
}

/// Scroll container that keeps the last card above the floating tab bar.
struct TabScreenScroll<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(WeatherViewModel.self) private var model
    @ViewBuilder var content: Content

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        ZStack {
            screenFill
            ScrollView {
                content
                    .padding(16)
                    .padding(.bottom, 28)
                    .foregroundStyle(theme.text)
            }
            .contentMargins(.bottom, 12, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)
        }
        .animation(.easeInOut(duration: 1.2), value: model.skyThemeName)
    }

    @ViewBuilder
    private var screenFill: some View {
        if colorScheme == .light, !model.skyThemeName.isEmpty {
            SkyBackdrop(name: model.skyThemeName)
        } else {
            theme.background.ignoresSafeArea()
        }
    }
}

struct WeatherCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    @ViewBuilder var content: Content

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.muted)
                .tracking(0.8)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.cardStroke, lineWidth: 1)
        )
    }
}
