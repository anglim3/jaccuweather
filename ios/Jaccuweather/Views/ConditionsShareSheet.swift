import LinkPresentation
import SwiftUI
import UIKit

final class ConditionsShareTextSource: NSObject, UIActivityItemSource {
    let summary: String
    let previewTitle: String

    init(summary: String, previewTitle: String) {
        self.summary = summary
        self.previewTitle = previewTitle
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        summary
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        summary
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        // The header is a single line, so the shared newlines would show only the place.
        // Facts go in the title; the Now link is the URL line under it.
        metadata.title = previewTitle
        if let link = summary.split(separator: "\n").last,
           let url = URL(string: String(link)), url.scheme != nil {
            metadata.originalURL = url
        }
        return metadata
    }
}

/// Toolbar control. Presents from the button's view controller so the system sheet is on screen.
struct ShareConditionsButton: UIViewRepresentable {
    var reading: ConditionsShareReading

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "square.and.arrow.up")
        config.contentInsets = .zero
        button.configuration = config
        button.accessibilityIdentifier = "share-conditions"
        button.accessibilityLabel = "Share current conditions"
        button.addTarget(context.coordinator, action: #selector(Coordinator.share(_:)), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.reading = reading
        button.isEnabled = ConditionsShareCopy.summary(reading) != nil
        button.tintColor = UIColor(JWPalette.dark.accent)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(width: 36, height: 36)
    }

    final class Coordinator: NSObject {
        var reading = ConditionsShareReading(
            placeName: "",
            temperatureF: nil,
            feelsLikeF: nil,
            conditionText: "",
            highF: nil,
            lowF: nil
        )

        @MainActor
        @objc func share(_ sender: UIButton) {
            guard let summary = ConditionsShareCopy.summary(reading),
                  let previewTitle = ConditionsShareCopy.previewTitle(reading) else { return }
            guard var presenter = sender.nearestViewController else { return }
            while let parent = presenter.parent {
                presenter = parent
            }
            let activity = UIActivityViewController(
                activityItems: [ConditionsShareTextSource(summary: summary, previewTitle: previewTitle)],
                applicationActivities: nil
            )
            if let popover = activity.popoverPresentationController {
                popover.sourceView = sender
                popover.sourceRect = sender.bounds
            }
            presenter.present(activity, animated: true)
        }
    }
}

private extension UIView {
    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let controller = next as? UIViewController { return controller }
            responder = next
        }
        return nil
    }
}
