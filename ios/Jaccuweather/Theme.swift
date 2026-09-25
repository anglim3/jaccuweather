import SwiftUI

/// Static deep-navy glass. Light and dark system appearances both use this palette.
struct JWPalette: Equatable {
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

    static func forScheme(_: ColorScheme) -> JWPalette { .dark }
}

/// Scroll container that keeps the last card above the floating tab bar.
struct TabScreenScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            JWPalette.dark.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(16)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(JWPalette.dark.text)
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
