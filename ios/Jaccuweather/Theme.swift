import SwiftUI
import UIKit

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

extension USAQIDisplay {
    /// Tailwind shades used by the website: green-400, yellow-400, orange-400,
    /// red-400, purple-400, and red-600 for Hazardous.
    var tint: Color {
        switch colorToken {
        case "green":
            return Color(red: 74 / 255, green: 222 / 255, blue: 128 / 255)
        case "yellow":
            return Color(red: 250 / 255, green: 204 / 255, blue: 21 / 255)
        case "orange":
            return Color(red: 251 / 255, green: 146 / 255, blue: 60 / 255)
        case "red":
            return Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255)
        case "purple":
            return Color(red: 192 / 255, green: 132 / 255, blue: 252 / 255)
        default:
            return Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)
        }
    }
}

/// Scroll container that keeps the last card above the floating tab bar.
struct TabScreenScroll<Content: View>: View {
    @Environment(WeatherViewModel.self) private var model
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(16)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(JWPalette.dark.text)
            .background {
                PullRefreshInstaller { await model.refresh() }
            }
        }
        .contentMargins(.bottom, 12, for: .scrollContent)
        .background(JWPalette.dark.background.ignoresSafeArea())
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
            control.tintColor = .white
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
