import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen banner and Dynamic Island for the current place.
/// Compact island: SF Symbol from the WMO code, plus temperature.
struct CurrentConditionsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WeatherActivityAttributes.self) { context in
            lockScreen(context.state)
                .activityBackgroundTint(WidgetHorizon.background)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbolName)
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(WidgetHorizon.accent)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(WeatherActivityText.degrees(context.state.temperatureF))
                        .font(.title2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(context.state.placeName)
                            .font(WidgetHorizon.placeFont(size: 16))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(context.state.conditionText)
                            .font(.subheadline)
                            .foregroundStyle(WidgetHorizon.muted)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.symbolName)
                    .font(.body.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(WidgetHorizon.accent)
                    .accessibilityLabel(context.state.conditionText)
            } compactTrailing: {
                Text(WeatherActivityText.degrees(context.state.temperatureF))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: context.state.symbolName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WidgetHorizon.accent)
                    .accessibilityLabel(context.state.conditionText)
            }
            .keylineTint(WidgetHorizon.accent)
        }
    }

    private func lockScreen(_ state: WeatherActivityAttributes.ContentState) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: state.symbolName)
                .font(.system(size: 30, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WidgetHorizon.accent)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.placeName)
                    .font(WidgetHorizon.placeFont(size: 17))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(state.conditionText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WidgetHorizon.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            Text(WeatherActivityText.degrees(state.temperatureF))
                .font(WidgetHorizon.tempFont(size: 40))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WeatherActivityText.spoken(state))
    }
}
