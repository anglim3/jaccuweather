import SwiftUI

/// Next place-local days: weekday, WMO symbol, high, low, and chance of precipitation.
/// Each column opens that day's sheet. A drop or snowflake sits with the percent when that day has one.
struct WatchDailyStrip: View {
    var days: [WatchDaySlot]
    var style: WatchStripStyle = .dailyRegular
    var onSelect: (WatchDaySlot) -> Void = { _ in }

    var body: some View {
        Group {
            if !days.isEmpty {
                strip
            }
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var strip: some View {
        GeometryReader { geo in
            let columns = WatchStripLayout.columns(container: geo.size.width, style: style)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: style.columnSpacing) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        column(day, emphasized: index == 0, width: columns.width)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(day) }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(WatchDailyPlan.stripSpoken(for: day))
                            .accessibilityIdentifier("watch-day-\(index)")
                    }
                }
                .padding(.horizontal, style.horizontalPadding)
                .padding(.vertical, style.verticalPadding)
            }
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    Color.clear.frame(width: columns.trailingMask)
                }
            }
            .background { cardShape.fill(WidgetHorizon.glass) }
            .clipShape(cardShape)
            .overlay { cardShape.strokeBorder(WidgetHorizon.glassBorder, lineWidth: 1) }
        }
        .frame(height: style.bandHeight)
        .accessibilityIdentifier("watch-daily-strip")
    }

    private func column(_ day: WatchDaySlot, emphasized: Bool, width: CGFloat) -> some View {
        let rows = rowHeights
        VStack(spacing: 0) {
            Text(day.label)
                .font(.system(size: style.labelSize, weight: .medium))
                .foregroundStyle(emphasized ? WidgetHorizon.text : WidgetHorizon.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: rows.label)
            Image(systemName: day.symbolName)
                .font(.system(size: style.symbolSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WidgetHorizon.accent)
                .frame(height: rows.symbol)
            Text(degrees(day.highF))
                .font(.system(size: style.primarySize, weight: .semibold))
                .foregroundStyle(WidgetHorizon.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .frame(height: rows.high)
            Text(degrees(day.lowF))
                .font(.system(size: style.secondarySize, weight: .medium))
                .foregroundStyle(WidgetHorizon.muted)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .frame(height: rows.low)
            precipLine(day, height: rows.precip)
        }
        .frame(width: width, height: style.bandHeight - style.verticalPadding * 2)
    }

    /// Label, symbol, high, and low keep a fixed box. The chance uses whatever height is left.
    private var rowHeights: (label: CGFloat, symbol: CGFloat, high: CGFloat, low: CGFloat, precip: CGFloat) {
        let label = style.labelSize + 2
        let symbol = style.cueHeight
        let high = style.primarySize + 3
        let low = style.secondarySize + 2
        let available = style.bandHeight - style.verticalPadding * 2
        let precip = available - label - symbol - high - low
        return (label, symbol, high, low, precip)
    }

    @ViewBuilder
    private func precipLine(_ day: WatchDaySlot, height: CGFloat) -> some View {
        let cue = WatchDailyPlan.stripCue(for: day)
        let showChance = WatchDailyPlan.showsStripPrecip(probability: day.precipProbability, cue: cue)
        if cue == .none, !showChance {
            Color.clear.frame(height: height)
        } else {
            HStack(spacing: 1) {
                cueSymbol(cue)
                if let chance = day.precipProbability, showChance {
                    Text("\(chance)%")
                        .font(.system(size: style.secondarySize, weight: .semibold))
                        .foregroundStyle(cue == .none ? WidgetHorizon.faint : WidgetHorizon.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .allowsTightening(true)
                }
            }
            .frame(height: height)
        }
    }

    @ViewBuilder
    private func cueSymbol(_ cue: WatchPrecipCue) -> some View {
        switch cue {
        case .snow:
            Image(systemName: "snowflake")
                .font(.system(size: cueSymbolSize, weight: .semibold))
                .foregroundStyle(WidgetHorizon.text)
        case .rain:
            Image(systemName: "drop.fill")
                .font(.system(size: cueSymbolSize, weight: .semibold))
                .foregroundStyle(WidgetHorizon.accent)
        case .none:
            EmptyView()
        }
    }

    /// Smaller than the day's WMO symbol so the percent still fits a 40mm column.
    private var cueSymbolSize: CGFloat {
        min(8, style.secondarySize)
    }

    private func degrees(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))°"
    }
}
