import SwiftUI

/// Next place-local days: weekday, WMO symbol, high, and low.
struct WatchDailyStrip: View {
    var days: [WatchDaySlot]

    var body: some View {
        Group {
            if !days.isEmpty {
                strip
            }
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 2) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    column(day, emphasized: index == 0)
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
        .frame(height: 60)
        .accessibilityIdentifier("watch-daily-strip")
    }

    private func column(_ day: WatchDaySlot, emphasized: Bool) -> some View {
        VStack(spacing: 0) {
            Text(day.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(emphasized ? WidgetHorizon.text : WidgetHorizon.muted)
            Image(systemName: day.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WidgetHorizon.accent)
                .frame(height: 14)
            Text(degrees(day.highF))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetHorizon.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(degrees(day.lowF))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WidgetHorizon.muted)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(width: 42, height: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(day))
    }

    private func degrees(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))°"
    }

    private func spoken(_ day: WatchDaySlot) -> String {
        "\(day.label), high \(degrees(day.highF)), low \(degrees(day.lowF))"
    }
}
