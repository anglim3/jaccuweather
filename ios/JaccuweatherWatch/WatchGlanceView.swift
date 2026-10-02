import SwiftUI

struct WatchGlanceView: View {
    var model: WatchWeatherModel

    var body: some View {
        ZStack {
            WidgetHorizonBackground()
                .ignoresSafeArea()
            VStack(spacing: 2) {
                Text(model.placeName)
                    .font(WidgetHorizon.placeFont(size: 15))
                    .foregroundStyle(WidgetHorizon.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                symbol
                    .padding(.top, 2)
                Text(model.temperatureText)
                    .font(WidgetHorizon.tempFont(size: 46))
                    .foregroundStyle(WidgetHorizon.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !model.detailText.isEmpty {
                    Text(model.detailText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetHorizon.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if !model.conditionText.isEmpty {
                    Text(model.conditionText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(WidgetHorizon.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.accessibilityLabel)
        }
        .preferredColorScheme(.dark)
        .task { await model.start() }
    }

    private var symbol: some View {
        Image(systemName: model.symbolName)
            .font(.system(size: 22, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(WidgetHorizon.accent)
            .frame(width: 40, height: 40)
            .background {
                Circle()
                    .fill(WidgetHorizon.glassStrong)
                    .overlay {
                        Circle().strokeBorder(WidgetHorizon.glassBorder, lineWidth: 1)
                    }
                    .overlay {
                        Circle().fill(
                            RadialGradient(
                                colors: [WidgetHorizon.accent.opacity(0.35), .clear],
                                center: .center,
                                startRadius: 2,
                                endRadius: 28
                            )
                        )
                    }
            }
            .accessibilityHidden(true)
    }
}
