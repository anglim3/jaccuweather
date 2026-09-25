import SwiftUI
import WebKit

/// Weather glyphs are animated SVG. The large Now icon keeps one web view so that
/// motion still plays. Every other glyph is a cached bitmap of the same artwork —
/// a web view per chip was the scroll and tab-switch cost.
struct SVGIconView: View {
    let fileName: String
    let folder: String
    var pointSize: CGFloat = 36
    var animates: Bool = false

    var body: some View {
        if animates {
            AnimatedSVGIcon(fileName: fileName, folder: folder, pointSize: pointSize)
                .frame(width: pointSize, height: pointSize)
        } else {
            RasterSVGIcon(fileName: fileName, folder: folder, pointSize: pointSize)
        }
    }
}

private struct RasterSVGIcon: View {
    let fileName: String
    let folder: String
    let pointSize: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Color.clear
            }
        }
        .frame(width: pointSize, height: pointSize)
        .task(id: "\(folder)/\(fileName)") {
            let rendered = await SVGIconRasterizer.shared.image(folder: folder, fileName: fileName)
            if !Task.isCancelled {
                image = rendered
            }
        }
    }
}

private struct AnimatedSVGIcon: UIViewRepresentable {
    let fileName: String
    let folder: String
    var pointSize: CGFloat = 36

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastKey = ""
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let key = "\(folder)/\(fileName)/\(Int(pointSize))"
        if context.coordinator.lastKey == key { return }
        context.coordinator.lastKey = key
        guard let html = SVGIconRasterizer.html(folder: folder, fileName: fileName, points: pointSize, stripMotion: false) else {
            return
        }
        webView.loadHTMLString(html, baseURL: nil)
    }
}

@MainActor
final class SVGIconRasterizer: NSObject {
    static let shared = SVGIconRasterizer()

    private final class Job {
        let key: String
        let html: String
        private let continuation: CheckedContinuation<UIImage?, Never>
        private var resumed = false

        init(key: String, html: String, continuation: CheckedContinuation<UIImage?, Never>) {
            self.key = key
            self.html = html
            self.continuation = continuation
        }

        func finish(_ image: UIImage?) {
            guard !resumed else { return }
            resumed = true
            continuation.resume(returning: image)
        }
    }

    private final class Slot: NSObject, WKNavigationDelegate {
        let webView: WKWebView
        var key: String?
        var onSnapshot: ((String, UIImage?) -> Void)?
        private var timeout: Task<Void, Never>?

        override init() {
            let config = WKWebViewConfiguration()
            config.suppressesIncrementalRendering = true
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 96, height: 96), configuration: config)
            view.isOpaque = false
            view.backgroundColor = .clear
            view.scrollView.isScrollEnabled = false
            view.scrollView.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            webView = view
            super.init()
            view.navigationDelegate = self
        }

        func load(key: String, html: String) {
            self.key = key
            timeout?.cancel()
            let expected = key
            timeout = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard self.key == expected else { return }
                self.finish(nil)
            }
            webView.loadHTMLString(html, baseURL: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let config = WKSnapshotConfiguration()
            config.rect = webView.bounds
            config.afterScreenUpdates = true
            let expected = key
            webView.takeSnapshot(with: config) { [weak self] image, _ in
                Task { @MainActor in
                    guard let self, self.key == expected else { return }
                    self.finish(image)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(nil)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(nil)
        }

        private func finish(_ image: UIImage?) {
            guard let key else { return }
            timeout?.cancel()
            self.key = nil
            onSnapshot?(key, image)
        }
    }

    private var memory: [String: UIImage] = [:]
    private var htmlCache: [String: String] = [:]
    private var waiters: [Job] = []
    private var inflight: [String: Job] = [:]
    private var followers: [String: [CheckedContinuation<UIImage?, Never>]] = [:]
    private var slots: [Slot] = []
    private var window: UIWindow?
    private let renderPoints: CGFloat = 96
    private let poolSize = 3

    func image(folder: String, fileName: String) async -> UIImage? {
        let name = fileName.hasSuffix(".svg") ? String(fileName.dropLast(4)) : fileName
        let key = "\(folder)/\(name)"
        if let cached = memory[key] { return cached }
        if let disk = Self.readDisk(key) {
            memory[key] = disk
            return disk
        }
        guard let html = html(folder: folder, fileName: fileName, points: renderPoints, stripMotion: true) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            if let cached = memory[key] {
                continuation.resume(returning: cached)
                return
            }
            if inflight[key] != nil || waiters.contains(where: { $0.key == key }) {
                followers[key, default: []].append(continuation)
                return
            }
            waiters.append(Job(key: key, html: html, continuation: continuation))
            pump()
        }
    }

    func html(folder: String, fileName: String, points: CGFloat, stripMotion: Bool) -> String? {
        Self.html(folder: folder, fileName: fileName, points: points, stripMotion: stripMotion, htmlCache: &htmlCache)
    }

    static func html(folder: String, fileName: String, points: CGFloat, stripMotion: Bool) -> String? {
        var cache: [String: String] = [:]
        return html(folder: folder, fileName: fileName, points: points, stripMotion: stripMotion, htmlCache: &cache)
    }

    private static func html(
        folder: String,
        fileName: String,
        points: CGFloat,
        stripMotion: Bool,
        htmlCache: inout [String: String]
    ) -> String? {
        let name = fileName.hasSuffix(".svg") ? String(fileName.dropLast(4)) : fileName
        let cacheKey = "\(folder)/\(name)/\(stripMotion)"
        if let cached = htmlCache[cacheKey] { return cached }
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Resources/Icons/\(folder)"),
            Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Icons/\(folder)")
        ]
        guard let url = candidates.compactMap({ $0 }).first,
              var svg = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        if stripMotion {
            svg = svg.replacingOccurrences(
                of: "<animateTransform\\b[^>]*/>|<animateTransform\\b[^>]*>[\\s\\S]*?</animateTransform>|<animate\\b[^>]*/>|<animate\\b[^>]*>[\\s\\S]*?</animate>",
                with: "",
                options: .regularExpression
            )
        }
        let px = Int(points.rounded())
        let html = """
        <html><head><meta name="viewport" content="width=\(px), initial-scale=1, maximum-scale=1">
        <style>html,body{margin:0;padding:0;background:transparent;overflow:hidden;width:\(px)px;height:\(px)px;} svg{width:\(px)px;height:\(px)px;display:block;}</style>
        </head><body>\(svg)</body></html>
        """
        htmlCache[cacheKey] = html
        return html
    }

    private func pump() {
        attachWindowIfNeeded()
        while inflight.count < poolSize, !waiters.isEmpty {
            let job = waiters.removeFirst()
            inflight[job.key] = job
            let slot = claimSlot()
            slot.onSnapshot = { [weak self] key, image in
                self?.complete(key: key, image: image)
            }
            slot.load(key: job.key, html: job.html)
        }
    }

    private func claimSlot() -> Slot {
        if let idle = slots.first(where: { $0.key == nil }) { return idle }
        let slot = Slot()
        let index = slots.count
        slot.webView.frame = CGRect(x: CGFloat(index) * 110, y: 0, width: 96, height: 96)
        window?.rootViewController?.view.addSubview(slot.webView)
        slots.append(slot)
        return slot
    }

    private func complete(key: String, image: UIImage?) {
        if let image {
            memory[key] = image
            Self.writeDisk(key, image: image)
        }
        inflight.removeValue(forKey: key)?.finish(image)
        let extras = followers.removeValue(forKey: key) ?? []
        for follower in extras {
            follower.resume(returning: image)
        }
        pump()
    }

    private func attachWindowIfNeeded() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let host = UIWindow(windowScene: scene)
        host.frame = CGRect(x: -1600, y: -1600, width: 430, height: 96)
        host.windowLevel = .init(rawValue: -1000)
        host.alpha = 0.02
        let root = UIViewController()
        root.view.backgroundColor = .clear
        host.rootViewController = root
        host.isHidden = false
        window = host
    }

    private static func diskURL(_ key: String) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jaccuweather-svg", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent(safe + ".png")
    }

    private static func readDisk(_ key: String) -> UIImage? {
        let url = diskURL(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data, scale: 3)
    }

    private static func writeDisk(_ key: String, image: UIImage) {
        guard let data = image.pngData() else { return }
        try? data.write(to: diskURL(key), options: .atomic)
    }
}
