import LinkPresentation
import SwiftUI
import UIKit

/// Offscreen card for the share sheet. The live hero icon is a web view, so this
/// draws the same words with ImageRenderer instead of snapshotting the screen.
struct ConditionsShareCard: View {
    let lines: [String]

    var body: some View {
        let theme = JWPalette.dark
        VStack(alignment: .leading, spacing: 6) {
            if let place = lines.first {
                Text(place)
                    .font(JWFont.location)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            if lines.count > 1 {
                Text(lines[1])
                    .font(JWFont.heroTemp)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            ForEach(Array(lines.dropFirst(2).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(theme.muted)
            }
        }
        .foregroundStyle(theme.text)
        .padding(28)
        .frame(width: 390, alignment: .leading)
        .background(
            LinearGradient(
                colors: [theme.backgroundTop, theme.background, theme.backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

enum ConditionsShareImage {
    @MainActor
    static func render(lines: [String]) -> UIImage? {
        guard !lines.isEmpty else { return nil }
        let renderer = ImageRenderer(content: ConditionsShareCard(lines: lines))
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.uiImage, image.size.width > 1, image.size.height > 1 else { return nil }
        return image
    }
}

final class ConditionsShareTextSource: NSObject, UIActivityItemSource {
    let summary: String
    let previewImage: UIImage?

    init(summary: String, previewImage: UIImage?) {
        self.summary = summary
        self.previewImage = previewImage
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
        metadata.title = summary
        if let previewImage {
            metadata.imageProvider = NSItemProvider(object: previewImage)
        }
        return metadata
    }
}

/// Presents the system share sheet from the Now tab without a second SwiftUI sheet.
struct ConditionsSharePresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var items: [Any]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.parent = self
        if isPresented {
            context.coordinator.present(from: controller)
        } else {
            context.coordinator.didPresent = false
        }
    }

    final class Coordinator {
        var parent: ConditionsSharePresenter
        var didPresent = false

        init(_ parent: ConditionsSharePresenter) {
            self.parent = parent
        }

        func present(from controller: UIViewController) {
            guard parent.isPresented, !didPresent else { return }
            guard controller.view.window != nil else { return }
            guard controller.presentedViewController == nil else { return }
            guard !parent.items.isEmpty else { return }
            didPresent = true
            let activity = UIActivityViewController(activityItems: parent.items, applicationActivities: nil)
            activity.completionWithItemsHandler = { _, _, _, _ in
                DispatchQueue.main.async {
                    self.parent.isPresented = false
                }
            }
            if let popover = activity.popoverPresentationController {
                popover.sourceView = controller.view
                let bounds = controller.view.bounds
                popover.sourceRect = CGRect(x: bounds.midX, y: bounds.minY, width: 1, height: 1)
                popover.permittedArrowDirections = []
            }
            controller.present(activity, animated: true)
        }
    }
}
