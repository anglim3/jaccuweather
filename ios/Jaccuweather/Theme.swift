import SwiftUI
import UIKit

/// Horizon tokens from the website (`:root` in `public/index.html`).
/// Light and dark system appearances both use this static navy glass palette.
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

    static func forScheme(_: ColorScheme) -> JWPalette { .dark }
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

enum JWFont {
    static let location = Font.system(size: 28, weight: .regular, design: .serif)
    static let heroTemp = Font.system(size: 72, weight: .light)
    static let section = Font.system(size: 16, weight: .semibold)
    static let eyebrow = Font.system(size: 12, weight: .semibold)
    static let statValue = Font.system(size: 20, weight: .bold)
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

/// Website `.bg-layer` without a weather class: navy gradient plus three glows.
struct HorizonBackground: View {
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
        .ignoresSafeArea()
    }
}

enum GlassRole {
    case hero, panel, stat, chip
}

private struct GlassBackground: ViewModifier {
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
    var prominence: GlassRole = .panel
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !title.isEmpty {
                Text(title)
                    .font(JWFont.section)
                    .tracking(-0.32)
                    .foregroundStyle(JWPalette.dark.text)
            }
            content
        }
        .padding(prominence == .hero ? JWMetrics.heroPadding : JWMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jwGlass(prominence)
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
