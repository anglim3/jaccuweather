import SwiftUI

/// Next place-local hours: temperature, chance of precipitation, and a rain or snow cue.
struct WatchHourlyStrip: View {
    var hours: [WatchHourSlot]

    var body: some View {
        Group {
            if !hours.isEmpty {
                strip
            }
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 2) {
                ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                    column(hour, emphasized: index == 0)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WidgetHorizon.glass)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(WidgetHorizon.glassBorder, lineWidth: 1)
                }
        }
        .frame(height: 56)
        .accessibilityIdentifier("watch-hourly-strip")
    }

    private func column(_ hour: WatchHourSlot, emphasized: Bool) -> some View {
        VStack(spacing: 0) {
            Text(hour.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(emphasized ? WidgetHorizon.text : WidgetHorizon.muted)
            Text(degrees(hour.temperatureF))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WidgetHorizon.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            cueLine(hour)
        }
        .frame(width: 40, height: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(hour))
    }

    @ViewBuilder
    private func cueLine(_ hour: WatchHourSlot) -> some View {
        let showChance = hour.precipProbability.map { $0 >= 10 || hour.cue != .none } ?? (hour.cue != .none)
        if hour.cue == .none, !showChance {
            Color.clear.frame(height: 14)
        } else {
            HStack(spacing: 1) {
                cueSymbol(hour.cue)
                if let chance = hour.precipProbability, showChance {
                    Text("\(chance)%")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(hour.cue == .none ? WidgetHorizon.faint : WidgetHorizon.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(height: 14)
        }
    }

    @ViewBuilder
    private func cueSymbol(_ cue: WatchPrecipCue) -> some View {
        switch cue {
        case .snow:
            Image(systemName: "snowflake")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WidgetHorizon.text)
        case .rain:
            Image(systemName: "drop.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WidgetHorizon.accent)
        case .none:
            EmptyView()
        }
    }

    private func degrees(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))°"
    }

    private func spoken(_ hour: WatchHourSlot) -> String {
        var parts = [hour.label, degrees(hour.temperatureF)]
        if let chance = hour.precipProbability {
            parts.append("\(chance) percent")
        }
        switch hour.cue {
        case .rain: parts.append("rain")
        case .snow: parts.append("snow")
        case .none: break
        }
        return parts.joined(separator: ", ")
    }
}
