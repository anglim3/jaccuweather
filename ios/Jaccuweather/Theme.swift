import SwiftUI

/// Glass colors for one appearance. Dark matches the site’s static deep blue.
/// Light is a pale glass palette with darker ink so text stays readable.
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
        card: Color.white.opacity(0.82),
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

/// Scroll container that keeps the last card above the floating tab bar.
struct TabScreenScroll<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            ScrollView {
                content
                    .padding(16)
                    .padding(.bottom, 28)
                    .foregroundStyle(theme.text)
            }
            .contentMargins(.bottom, 12, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)
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
