import SwiftUI

/// Dark glass palette loosely aligned with the web app (deep blue + sky accent).
enum JWTheme {
    static let background = Color(red: 13 / 255, green: 33 / 255, blue: 55 / 255)
    static let card = Color.white.opacity(0.08)
    static let cardStroke = Color.white.opacity(0.12)
    static let accent = Color(red: 125 / 255, green: 211 / 255, blue: 252 / 255)
    static let muted = Color.white.opacity(0.65)
    static let gold = Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255)
}

struct WeatherCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(JWTheme.muted)
                .tracking(0.8)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JWTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(JWTheme.cardStroke, lineWidth: 1)
        )
    }
}
