import SwiftUI
import WidgetKit

/// Debug-only board for the four complication slots.
/// Launch with `-complicationGallery 1` plus a pinned place.
enum WatchComplicationGalleryLaunch {
    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains("-complicationGallery")
    }
}

struct WatchComplicationGallery: View {
    var snapshot: WidgetConditionsSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.locationName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetHorizon.text)
                    .accessibilityIdentifier("watch-complication-gallery")
                slot("Inline", family: .accessoryInline, height: 36)
                HStack(alignment: .top, spacing: 6) {
                    slot("Corner", family: .accessoryCorner, height: 78)
                    slot("Circular", family: .accessoryCircular, height: 64)
                }
                slot("Rectangular", family: .accessoryRectangular, height: 64)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .background(WidgetHorizonBackground())
    }

    private func slot(_ title: String, family: WidgetFamily, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(WidgetHorizon.muted)
            WatchComplicationView(
                entry: WatchComplicationEntry(date: Date(), snapshot: snapshot),
                familyOverride: family
            )
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
