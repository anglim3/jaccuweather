import SwiftUI

/// Horizon tokens from the website `:root` in `public/index.html`.
/// Duplicated here so the widget does not take a dependency on `Theme.swift`.
enum WidgetHorizon {
    static let backgroundTop = Color(red: 26 / 255, green: 58 / 255, blue: 92 / 255)
    static let background = Color(red: 13 / 255, green: 33 / 255, blue: 55 / 255)
    static let backgroundBottom = Color(red: 10 / 255, green: 22 / 255, blue: 40 / 255)
    static let accent = Color(red: 125 / 255, green: 211 / 255, blue: 252 / 255)
    static let gold = Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255)
    static let indigo = Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255)
    static let glass = Color.white.opacity(0.12)
    static let glassStrong = Color.white.opacity(0.18)
    static let glassBorder = Color.white.opacity(0.22)
    static let muted = Color.white.opacity(0.72)
    static let faint = Color.white.opacity(0.48)
    static let text = Color.white

    static func placeFont(size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static func tempFont(size: CGFloat) -> Font {
        .system(size: size, weight: .light)
    }
}

/// Website `.bg-layer` without a weather class: 165° navy plus the three glows.
struct WidgetHorizonBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: WidgetHorizon.backgroundTop, location: 0),
                    .init(color: WidgetHorizon.background, location: 0.55),
                    .init(color: WidgetHorizon.backgroundBottom, location: 1)
                ],
                startPoint: UnitPoint(x: 0.42, y: 0),
                endPoint: UnitPoint(x: 0.58, y: 1)
            )
            RadialGradient(
                colors: [WidgetHorizon.accent.opacity(0.35), .clear],
                center: UnitPoint(x: 0.20, y: 0.10),
                startRadius: 0,
                endRadius: 220
            )
            RadialGradient(
                colors: [WidgetHorizon.gold.opacity(0.20), .clear],
                center: UnitPoint(x: 0.88, y: 0.12),
                startRadius: 0,
                endRadius: 180
            )
            RadialGradient(
                colors: [WidgetHorizon.indigo.opacity(0.30), .clear],
                center: UnitPoint(x: 0.50, y: 1.02),
                startRadius: 0,
                endRadius: 200
            )
            LinearGradient(
                colors: [Color.white.opacity(0.10), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.42)
            )
        }
    }
}

/// Website glass chip: white fill at `--glass` and a `--glass-border` stroke.
struct WidgetGlassLabel: View {
    var text: String
    var fullColor: Bool
    var foreground: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background {
                if fullColor {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WidgetHorizon.glass)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(WidgetHorizon.glassBorder, lineWidth: 1)
                        }
                }
            }
    }
}
