import SwiftUI
import WebKit

/// Meteocon weather and alert icons animate with SMIL, which a bitmap snapshot
/// freezes and can crop. Each on-screen glyph gets a web view sized to its
/// frame; hourly chips stay in a lazy stack, and views are recycled when they
/// leave the screen. Card art has no SMIL and uses the same renderer so those
/// glyphs stay the full viewBox.
struct SVGIconView: View {
    let fileName: String
    let folder: String
    var pointSize: CGFloat = 36

    var body: some View {
        SVGWebIcon(fileName: fileName, folder: folder)
            .frame(width: pointSize, height: pointSize)
            .accessibilityHidden(true)
    }
}

private struct SVGWebIcon: UIViewRepresentable {
    let fileName: String
    let folder: String

    func makeUIView(context: Context) -> SVGIconHostView {
        SVGWebViewPool.take()
    }

    func updateUIView(_ uiView: SVGIconHostView, context: Context) {
        uiView.configure(folder: folder, fileName: fileName)
    }

    static func dismantleUIView(_ uiView: SVGIconHostView, coordinator: Void) {
        SVGWebViewPool.recycle(uiView)
    }
}

/// Ignores the phone safe area. A 28–72pt web view otherwise insets its
/// scroll view and the glyph draws shifted and clipped.
private final class IconWebView: WKWebView {
    override var safeAreaInsets: UIEdgeInsets { .zero }
}

private final class SVGIconHostView: UIView, WKNavigationDelegate {
    private let webView: IconWebView
    private var folder = ""
    private var fileName = ""
    private var loadedKey = ""

    override init(frame: CGRect) {
        let web = IconWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.isOpaque = false
        web.backgroundColor = .clear
        web.underPageBackgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.backgroundColor = .clear
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.contentInset = .zero
        web.scrollView.scrollIndicatorInsets = .zero
        web.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        web.isUserInteractionEnabled = false
        web.insetsLayoutMarginsFromSafeArea = false
        web.scrollView.insetsLayoutMarginsFromSafeArea = false
        webView = web
        super.init(frame: frame)
        insetsLayoutMarginsFromSafeArea = false
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = true
        web.navigationDelegate = self
        addSubview(web)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var safeAreaInsets: UIEdgeInsets { .zero }

    func configure(folder: String, fileName: String) {
        self.folder = folder
        self.fileName = fileName
        loadIfReady()
    }

    func prepareForReuse() {
        loadedKey = ""
        folder = ""
        fileName = ""
        webView.stopLoading()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        webView.frame = bounds
        loadIfReady()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.scrollView.contentInset = .zero
        webView.scrollView.contentOffset = .zero
    }

    private func loadIfReady() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let name = Self.bareName(fileName)
        guard !folder.isEmpty, !name.isEmpty else { return }
        let points = Int(bounds.width.rounded())
        let key = "\(folder)/\(name)/\(points)"
        guard key != loadedKey else { return }
        guard let html = SVGIconDocument.html(folder: folder, fileName: name, points: points) else { return }
        loadedKey = key
        webView.scrollView.contentInset = .zero
        webView.loadHTMLString(html, baseURL: SVGIconDocument.baseURL(folder: folder, fileName: name))
    }

    private static func bareName(_ fileName: String) -> String {
        fileName.hasSuffix(".svg") ? String(fileName.dropLast(4)) : fileName
    }
}

private enum SVGIconDocument {
    private static var pages: [String: String] = [:]

    static func html(folder: String, fileName: String, points: Int) -> String? {
        let key = "\(folder)/\(fileName)/\(points)"
        if let cached = pages[key] { return cached }
        guard let url = locate(folder: folder, fileName: fileName),
              let svg = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let px = points
        let html = """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=\(px), initial-scale=1, minimum-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
        <style>
          html,body{margin:0;padding:0;background:transparent;overflow:hidden;width:\(px)px;height:\(px)px;}
          svg{width:\(px)px;height:\(px)px;display:block;}
        </style>
        </head><body>\(svg)</body></html>
        """
        pages[key] = html
        return html
    }

    static func baseURL(folder: String, fileName: String) -> URL? {
        locate(folder: folder, fileName: fileName)?.deletingLastPathComponent()
    }

    private static func locate(folder: String, fileName: String) -> URL? {
        let candidates = [
            Bundle.main.url(forResource: fileName, withExtension: "svg", subdirectory: "Icons/\(folder)"),
            Bundle.main.url(forResource: fileName, withExtension: "svg", subdirectory: "Resources/Icons/\(folder)")
        ]
        return candidates.compactMap { $0 }.first
    }
}

@MainActor
private enum SVGWebViewPool {
    private static var spare: [SVGIconHostView] = []
    private static let limit = 12
    private static let droppedStaleBitmaps: Bool = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jaccuweather-svg", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        return true
    }()

    static func take() -> SVGIconHostView {
        _ = droppedStaleBitmaps
        if let view = spare.popLast() { return view }
        return SVGIconHostView(frame: .zero)
    }

    static func recycle(_ view: SVGIconHostView) {
        view.prepareForReuse()
        guard spare.count < limit else { return }
        spare.append(view)
    }
}
