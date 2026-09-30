import SwiftUI
import UIKit

/// Horizon glass tokens from the website (`:root` in `public/index.html`).
/// Both appearances keep this white-on-glass palette. Dark paints the static
/// navy field; light paints a weather sky behind the same cards.
struct JWPalette: Equatable {
    let backgroundTop: Color
    let background: Color
    let backgroundBottom: Color
    let card: Color
    let glassStrong: Color
    let cardStroke: Color
    let stat: Color
    let statStroke: Color
    let chip: Color
    let chipStroke: Color
    let accent: Color
    let muted: Color
    let faint: Color
    let gold: Color
    let text: Color
    let tile: Color
    let grid: Color
    let divider: Color
    let cloudLow: Color
    let cloudMid: Color
    let cloudHigh: Color
    let sunStroke: Color
    let moon: Color

    static let dark = JWPalette(
        backgroundTop: Color(red: 26 / 255, green: 58 / 255, blue: 92 / 255),
        background: Color(red: 13 / 255, green: 33 / 255, blue: 55 / 255),
        backgroundBottom: Color(red: 10 / 255, green: 22 / 255, blue: 40 / 255),
        card: Color.white.opacity(0.12),
        glassStrong: Color.white.opacity(0.18),
        cardStroke: Color.white.opacity(0.22),
        stat: Color.white.opacity(0.06),
        statStroke: Color.white.opacity(0.08),
        chip: Color.white.opacity(0.05),
        chipStroke: Color.white.opacity(0.08),
        accent: Color(red: 125 / 255, green: 211 / 255, blue: 252 / 255),
        muted: Color.white.opacity(0.72),
        faint: Color.white.opacity(0.48),
        gold: Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255),
        text: .white,
        tile: Color.white.opacity(0.08),
        grid: Color.white.opacity(0.08),
        divider: Color.white.opacity(0.10),
        cloudLow: Color(red: 100 / 255, green: 116 / 255, blue: 139 / 255).opacity(0.9),
        cloudMid: Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255).opacity(0.9),
        cloudHigh: Color(red: 203 / 255, green: 213 / 255, blue: 225 / 255).opacity(0.9),
        sunStroke: Color.white.opacity(0.18),
        moon: Color(red: 226 / 255, green: 232 / 255, blue: 240 / 255)
    )

    /// Ignores the system scheme. The app forces dark chrome so type stays white
    /// on both the navy field and the weather skies.
    static func forScheme(_: ColorScheme) -> JWPalette { .dark }
}

/// Website `localStorage` key `jaccuweather-theme`. Missing or unknown values stay dark.
enum JWAppearance: String {
    case dark
    case light

    static let storageKey = "jaccuweather-theme"

    static var stored: JWAppearance {
        UserDefaults.standard.string(forKey: storageKey) == JWAppearance.light.rawValue ? .light : .dark
    }
}

/// Website `.bg-layer` class names from `WMO_THEMES` / `setTheme`.
enum JWSky: Hashable {
    case navy
    case sunny
    case clearNight
    case cloudy
    case rainy
    case storm
    case snow
    case fog

    var title: String {
        switch self {
        case .navy: return "Navy"
        case .sunny: return "Clear"
        case .clearNight: return "Clear night"
        case .cloudy: return "Cloudy"
        case .rainy: return "Rain"
        case .storm: return "Storm"
        case .snow: return "Snow"
        case .fog: return "Fog"
        }
    }

    /// Snow and fog gradients are light enough that glass needs a darker frost.
    var needsDarkerGlass: Bool { self == .snow || self == .fog }

    /// Same mapping as `WMO_THEMES`, including clear / mainly clear at night.
    static func matching(weatherCode: Int?, isDay: Bool) -> JWSky {
        guard let weatherCode else { return .cloudy }
        if !isDay && (weatherCode == 0 || weatherCode == 1) {
            return .clearNight
        }
        switch weatherCode {
        case 0, 1:
            return .sunny
        case 2, 3:
            return .cloudy
        case 45, 48:
            return .fog
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81:
            return .rainy
        case 71, 73, 75, 77, 85, 86:
            return .snow
        case 82, 95, 96, 99:
            return .storm
        default:
            return .cloudy
        }
    }
}

/// ApexCharts series colors from the website forecast modals.
enum JWChart {
    static let rose = Color(red: 255 / 255, green: 99 / 255, blue: 132 / 255)
    static let blue = Color(red: 54 / 255, green: 162 / 255, blue: 235 / 255)
    static let wind = Color(red: 255 / 255, green: 206 / 255, blue: 86 / 255)
    static let violet = Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255)
    static let teal = Color(red: 75 / 255, green: 192 / 255, blue: 192 / 255)
    static let green = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
    static let snow = Color(red: 176 / 255, green: 196 / 255, blue: 222 / 255)
    static let orange = Color(red: 251 / 255, green: 146 / 255, blue: 60 / 255)
    static let sky = Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255)
    static let lime = Color(red: 132 / 255, green: 204 / 255, blue: 22 / 255)
    static let sun = Color(red: 250 / 255, green: 204 / 255, blue: 21 / 255)
    static let tide = Color(red: 6 / 255, green: 182 / 255, blue: 212 / 255)
    static let moon = Color(red: 147 / 255, green: 112 / 255, blue: 219 / 255)

    static func line(_ series: String) -> Color {
        switch series {
        case "temp": return rose
        case "feelslike": return orange
        case "niceweather": return lime
        case "precip": return blue
        case "wind": return wind
        case "uv": return violet
        case "humidity": return teal
        case "pressure": return green
        case "snow": return snow
        case "brightness": return sun
        case "tides": return tide
        case "moon": return moon
        default: return JWPalette.dark.accent
        }
    }

    static func high(_ series: String) -> Color {
        series == "feelslike" ? orange : rose
    }

    static func low(_ series: String) -> Color {
        series == "feelslike" ? sky : blue
    }

    static func area(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.32), color.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Website risk and pollen label colors (`text-green-400` and the rest).
enum JWTone {
    static let green = Color(red: 74 / 255, green: 222 / 255, blue: 128 / 255)
    static let lime = Color(red: 163 / 255, green: 230 / 255, blue: 53 / 255)
    static let yellow = Color(red: 250 / 255, green: 204 / 255, blue: 21 / 255)
    static let orange = Color(red: 251 / 255, green: 146 / 255, blue: 60 / 255)
    static let red = Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255)
    static let blue = Color(red: 147 / 255, green: 197 / 255, blue: 253 / 255)

    static func color(forColorClass colorClass: String?) -> Color {
        switch colorClass {
        case "text-green-400", "text-green-300": return green
        case "text-lime-400": return lime
        case "text-yellow-400", "text-yellow-300": return yellow
        case "text-orange-400", "text-orange-300": return orange
        case "text-red-400", "text-red-300", "text-red-600": return red
        case "text-blue-300": return blue
        default: return JWPalette.dark.muted
        }
    }

    static func color(forLabel label: String) -> Color {
        switch label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "low", "excellent": return green
        case "nice": return lime
        case "moderate", "elevated", "fair": return yellow
        case "high": return orange
        case "very high", "poor": return red
        default: return JWPalette.dark.faint
        }
    }
}

enum JWFont {
    static let location = Font.system(size: 28, weight: .regular, design: .serif)
    static let heroTemp = Font.system(size: 72, weight: .light)
    static let section = Font.system(size: 16, weight: .semibold)
    static let eyebrow = Font.system(size: 12, weight: .semibold)
    static let statValue = Font.system(size: 20, weight: .bold)
    static let body = Font.system(size: 15, weight: .regular)
    static let chipTime = Font.system(size: 13, weight: .medium)
    static let chipValue = Font.system(size: 18, weight: .bold)
    static let dayName = Font.system(size: 16, weight: .semibold)
    static let dayHigh = Font.system(size: 18, weight: .bold)
}

enum JWMetrics {
    static let radius: CGFloat = 20
    static let radiusSm: CGFloat = 12
    static let radiusChip: CGFloat = 8
    static let panelPadding: CGFloat = 20
    static let heroPadding: CGFloat = 22
    static let sectionGap: CGFloat = 20
}

/// Page background. Dark is the static navy `.bg-layer`. Light uses the weather class.
struct HorizonBackground: View {
    @Environment(WeatherViewModel.self) private var model

    var body: some View {
        let sky = model.pageSky
        ZStack {
            NavyHorizonFill()
                .opacity(sky == .navy ? 1 : 0)
            ForEach(JWSky.weatherSkies, id: \.self) { candidate in
                WeatherSkyFill(sky: candidate)
                    .opacity(candidate == sky ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.2), value: sky)
    }
}

/// Website `.bg-layer` without a weather class: navy gradient plus three glows.
private struct NavyHorizonFill: View {
    var body: some View {
        let theme = JWPalette.dark
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: theme.backgroundTop, location: 0),
                    .init(color: theme.background, location: 0.55),
                    .init(color: theme.backgroundBottom, location: 1)
                ],
                startPoint: UnitPoint(x: 0.42, y: 0),
                endPoint: UnitPoint(x: 0.58, y: 1)
            )
            RadialGradient(
                colors: [theme.accent.opacity(0.35), .clear],
                center: UnitPoint(x: 0.20, y: 0.10),
                startRadius: 0,
                endRadius: 340
            )
            RadialGradient(
                colors: [theme.gold.opacity(0.20), .clear],
                center: UnitPoint(x: 0.85, y: 0.20),
                startRadius: 0,
                endRadius: 300
            )
            RadialGradient(
                colors: [Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255).opacity(0.30), .clear],
                center: UnitPoint(x: 0.50, y: 0.92),
                startRadius: 0,
                endRadius: 320
            )
        }
    }
}

/// Website `.bg-layer.sunny` and the other weather classes.
private struct WeatherSkyFill: View {
    var sky: JWSky

    var body: some View {
        let paint = sky.paint
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            ZStack {
                LinearGradient(stops: paint.stops, startPoint: paint.start, endPoint: paint.end)
                skyGlow(paint.primary, width: width, height: height)
                if let secondary = paint.secondary {
                    skyGlow(secondary, width: width, height: height)
                }
            }
        }
    }

    private func skyGlow(_ glow: SkyGlow, width: CGFloat, height: CGFloat) -> some View {
        RadialGradient(
            colors: [glow.color, .clear],
            center: glow.center,
            startRadius: 0,
            endRadius: max(width * glow.radiusX, height * glow.radiusY) * glow.fade
        )
    }
}

private struct SkyGlow {
    var color: Color
    var center: UnitPoint
    var radiusX: CGFloat
    var radiusY: CGFloat
    var fade: CGFloat
}

private struct SkyPaint {
    var stops: [Gradient.Stop]
    var start: UnitPoint
    var end: UnitPoint
    var primary: SkyGlow
    var secondary: SkyGlow?
}

private extension JWSky {
    static let weatherSkies: [JWSky] = [.sunny, .clearNight, .cloudy, .rainy, .storm, .snow, .fog]

    var paint: SkyPaint {
        switch self {
        case .sunny:
            return SkyPaint(
                stops: [
                    .init(color: skyRGB(59, 130, 246), location: 0),
                    .init(color: skyRGB(14, 165, 233), location: 0.40),
                    .init(color: skyRGB(3, 105, 161), location: 1)
                ],
                start: cssGradientStart(160),
                end: cssGradientEnd(160),
                primary: SkyGlow(
                    color: skyRGB(251, 191, 36, 0.45),
                    center: UnitPoint(x: 0.70, y: 0),
                    radiusX: 0.90,
                    radiusY: 0.70,
                    fade: 0.50
                ),
                secondary: SkyGlow(
                    color: skyRGB(56, 189, 248, 0.25),
                    center: UnitPoint(x: 0.10, y: 0.80),
                    radiusX: 0.60,
                    radiusY: 0.40,
                    fade: 0.50
                )
            )
        case .clearNight:
            return SkyPaint(
                stops: [
                    .init(color: skyRGB(15, 23, 42), location: 0),
                    .init(color: skyRGB(30, 27, 75), location: 0.50),
                    .init(color: skyRGB(12, 10, 29), location: 1)
                ],
                start: cssGradientStart(165),
                end: cssGradientEnd(165),
                primary: SkyGlow(
                    color: Color.white.opacity(0.15),
                    center: UnitPoint(x: 0.80, y: 0.15),
                    radiusX: 0.40,
                    radiusY: 0.30,
                    fade: 0.40
                ),
                secondary: SkyGlow(
                    color: skyRGB(99, 102, 241, 0.35),
                    center: UnitPoint(x: 0.20, y: 0.70),
                    radiusX: 0.70,
                    radiusY: 0.50,
                    fade: 0.50
                )
            )
        case .rainy:
            return SkyPaint(
                stops: [
                    .init(color: skyRGB(30, 58, 95), location: 0),
                    .init(color: skyRGB(15, 39, 68), location: 0.40),
                    .init(color: skyRGB(12, 25, 41), location: 1)
                ],
                start: cssGradientStart(165),
                end: cssGradientEnd(165),
                primary: SkyGlow(
                    color: skyRGB(100, 116, 139, 0.40),
                    center: UnitPoint(x: 0.50, y: 0),
                    radiusX: 0.70,
                    radiusY: 0.50,
                    fade: 0.50
                ),
                secondary: nil
            )
        case .storm:
            return SkyPaint(
                stops: [
                    .init(color: skyRGB(30, 27, 75), location: 0),
                    .init(color: skyRGB(15, 23, 42), location: 0.50),
                    .init(color: skyRGB(2, 6, 23), location: 1)
                ],
                start: cssGradientStart(165),
                end: cssGradientEnd(165),
                primary: SkyGlow(
                    color: skyRGB(139, 92, 246, 0.30),
                    center: UnitPoint(x: 0.70, y: 0.30),
                    radiusX: 0.60,
                    radiusY: 0.40,
                    fade: 0.50
                ),
                secondary: nil
            )
        case .snow:
            return SkyPaint(
                stops: [
                    .init(color: skyRGB(148, 163, 184), location: 0),
                    .init(color: skyRGB(100, 116, 139), location: 0.40),
                    .init(color: skyRGB(51, 65, 85), location: 1)
                ],
                start: cssGradientStart(165),
                end: cssGradientEnd(165),
                primary: SkyGlow(
                    color: skyRGB(226, 232, 240, 0.40),
                    center: UnitPoint(x: 0.40, y: 0.10),
                    radiusX: 0.80,
                    radiusY: 0.50,
                    fade: 0.50
                ),
                secondary: nil
            )
        case .fog:
            return SkyPaint(
                stops: [
                    .init(color: skyRGB(100, 116, 139), location: 0),
                    .init(color: skyRGB(71, 85, 105), location: 0.50),
                    .init(color: skyRGB(51, 65, 85), location: 1)
                ],
                start: cssGradientStart(165),
                end: cssGradientEnd(165),
                primary: SkyGlow(
                    color: skyRGB(203, 213, 225, 0.25),
                    center: UnitPoint(x: 0.50, y: 0.40),
                    radiusX: 1.0,
                    radiusY: 0.60,
                    fade: 0.60
                ),
                secondary: nil
            )
        case .cloudy, .navy:
            return SkyPaint(
                stops: [
                    .init(color: skyRGB(71, 85, 105), location: 0),
                    .init(color: skyRGB(51, 65, 85), location: 0.50),
                    .init(color: skyRGB(30, 41, 59), location: 1)
                ],
                start: cssGradientStart(165),
                end: cssGradientEnd(165),
                primary: SkyGlow(
                    color: skyRGB(148, 163, 184, 0.35),
                    center: UnitPoint(x: 0.30, y: 0.20),
                    radiusX: 0.80,
                    radiusY: 0.50,
                    fade: 0.50
                ),
                secondary: nil
            )
        }
    }
}

/// CSS `linear-gradient` angle: 0° points up, clockwise. 165° runs down and slightly right.
private func cssGradientStart(_ degrees: Double) -> UnitPoint {
    let vector = cssGradientVector(degrees)
    return UnitPoint(x: 0.5 - vector.dx * 0.5, y: 0.5 - vector.dy * 0.5)
}

private func cssGradientEnd(_ degrees: Double) -> UnitPoint {
    let vector = cssGradientVector(degrees)
    return UnitPoint(x: 0.5 + vector.dx * 0.5, y: 0.5 + vector.dy * 0.5)
}

private func cssGradientVector(_ degrees: Double) -> (dx: CGFloat, dy: CGFloat) {
    let radians = degrees * .pi / 180
    return (dx: CGFloat(sin(radians)), dy: CGFloat(-cos(radians)))
}

private func skyRGB(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> Color {
    Color(red: red / 255, green: green / 255, blue: blue / 255, opacity: alpha)
}

enum GlassRole {
    case hero, panel, stat, chip
}

private struct GlassBackground: ViewModifier {
    @Environment(WeatherViewModel.self) private var model
    var role: GlassRole
    var theme: JWPalette = .dark

    private var radius: CGFloat {
        switch role {
        case .hero, .panel: return JWMetrics.radius
        case .stat, .chip: return JWMetrics.radiusSm
        }
    }

    private var fill: Color {
        switch role {
        case .hero: return theme.glassStrong
        case .panel: return theme.card
        case .stat: return theme.stat
        case .chip: return theme.chip
        }
    }

    private var stroke: Color {
        switch role {
        case .hero, .panel: return theme.cardStroke
        case .stat: return theme.statStroke
        case .chip: return theme.chipStroke
        }
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    if role == .hero || role == .panel {
                        shape.fill(.ultraThinMaterial).opacity(role == .hero ? 0.22 : 0.16)
                    }
                    if model.pageSky.needsDarkerGlass && (role == .hero || role == .panel) {
                        shape.fill(Color.black.opacity(0.42))
                    }
                    shape.fill(fill)
                    if role == .hero {
                        shape.fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.05), .clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.38)
                            )
                        )
                    }
                }
            }
            .overlay {
                shape.strokeBorder(stroke, lineWidth: 1).allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                if role == .hero {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [theme.accent.opacity(0.18), .clear],
                                center: .center,
                                startRadius: 8,
                                endRadius: 160
                            )
                        )
                        .frame(width: 280, height: 280)
                        .offset(x: 70, y: -90)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(shape)
            .shadow(
                color: .black.opacity(role == .hero ? 0.28 : (role == .panel ? 0.18 : 0)),
                radius: role == .hero ? 30 : 16,
                y: role == .hero ? 18 : 8
            )
    }
}

extension View {
    func jwGlass(_ role: GlassRole) -> some View {
        modifier(GlassBackground(role: role))
    }

    func jwScreenChrome() -> some View {
        self
            .foregroundStyle(JWPalette.dark.text)
            .background { HorizonBackground() }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(JWPalette.dark.accent)
    }
}

enum CardTitleStyle {
    case eyebrow
    case section
}

struct SectionEyebrow: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(JWFont.eyebrow)
            .tracking(1.1)
            .foregroundStyle(JWPalette.dark.muted)
    }
}

struct StatLabel: View {
    let title: String
    var icon: String?

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                SVGIconView(fileName: icon + ".svg", folder: "cards", pointSize: 18)
                    .frame(width: 22, height: 22)
            }
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 156 / 255, green: 163 / 255, blue: 175 / 255))
                .lineLimit(1)
        }
    }
}

/// Open-Meteo CC BY 4.0 credit shown under forecast data.
struct OpenMeteoCreditLine: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Link(destination: APIEndpoints.openMeteo) {
                Text("Weather data by Open-Meteo.com")
                    .font(.caption.weight(.semibold))
                    .underline()
            }
            Link(destination: APIEndpoints.ccBy4) {
                Text("CC BY 4.0")
                    .font(.caption.weight(.semibold))
                    .underline()
            }
            Text("Ensemble values are averaged for display.")
                .font(.caption2)
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(theme.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("open-meteo-credit")
        .padding(.top, 4)
    }
}

/// Scroll container that keeps the last card above the floating tab bar.
struct TabScreenScroll<Content: View>: View {
    @Environment(WeatherViewModel.self) private var model
    var scrollTo: String? = nil
    @ViewBuilder var content: Content

    private func revealAnchor(_ proxy: ScrollViewProxy) {
        guard let scrollTo else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            proxy.scrollTo(scrollTo, anchor: .top)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: JWMetrics.sectionGap) {
                    content
                    OpenMeteoCreditLine()
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 88)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(JWPalette.dark.text)
                .background {
                    PullRefreshInstaller { await model.refresh() }
                }
            }
            .onAppear { revealAnchor(proxy) }
            .onChange(of: scrollTo) { _, _ in revealAnchor(proxy) }
            .onChange(of: model.dailyRows.count) { _, _ in revealAnchor(proxy) }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 12, for: .scrollContent)
        .background { HorizonBackground() }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

/// Hooks the tab scroll view up to a refresh control. `.refreshable` on this
/// container only rubber-bands; the control is what reloads the forecast.
private struct PullRefreshInstaller: UIViewRepresentable {
    var action: @MainActor () async -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.action = action
        DispatchQueue.main.async {
            guard let scroll = uiView.enclosingScrollView() else { return }
            if scroll.refreshControl !== context.coordinator.control {
                scroll.refreshControl = context.coordinator.control
            }
        }
    }

    final class Coordinator: NSObject {
        var action: @MainActor () async -> Void
        let control: UIRefreshControl

        init(action: @escaping @MainActor () async -> Void) {
            self.action = action
            let control = UIRefreshControl()
            control.tintColor = UIColor(red: 125 / 255, green: 211 / 255, blue: 252 / 255, alpha: 1)
            self.control = control
            super.init()
            control.addTarget(self, action: #selector(fire), for: .valueChanged)
        }

        @objc private func fire() {
            let action = action
            let control = control
            Task { @MainActor in
                await action()
                control.endRefreshing()
            }
        }
    }
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        var view: UIView? = self
        while let current = view {
            if let scroll = current as? UIScrollView { return scroll }
            view = current.superview
        }
        return nil
    }
}

struct WeatherCard<Content: View>: View {
    var title: String
    var titleStyle: CardTitleStyle = .section
    var prominence: GlassRole = .panel
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !title.isEmpty {
                titleLabel
            }
            content
        }
        .padding(prominence == .hero ? JWMetrics.heroPadding : JWMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jwGlass(prominence)
    }

    @ViewBuilder
    private var titleLabel: some View {
        switch titleStyle {
        case .eyebrow:
            Text(title.uppercased())
                .font(JWFont.eyebrow)
                .tracking(0.8)
                .foregroundStyle(JWPalette.dark.muted)
        case .section:
            Text(title)
                .font(JWFont.section)
                .tracking(-0.32)
                .foregroundStyle(JWPalette.dark.text)
        }
    }
}

/// Forecast section: sentence-case header with the chart menu on the right.
struct ForecastPanel<Accessory: View, Content: View>: View {
    let title: String
    var accessory: Accessory
    var content: Content

    init(title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(JWFont.section)
                    .tracking(-0.32)
                    .foregroundStyle(JWPalette.dark.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                accessory
            }
            content
        }
        .padding(JWMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jwGlass(.panel)
    }
}
