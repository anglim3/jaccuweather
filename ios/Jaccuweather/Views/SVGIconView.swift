import SwiftUI
import WebKit

struct SVGIconView: UIViewRepresentable {
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
        let name = fileName.hasSuffix(".svg") ? String(fileName.dropLast(4)) : fileName
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Resources/Icons/\(folder)"),
            Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Icons/\(folder)")
        ]
        guard let url = candidates.compactMap({ $0 }).first, let svg = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        let html = """
        <html><head><meta name="viewport" content="width=\(Int(pointSize)), initial-scale=1">
        <style>html,body{margin:0;padding:0;background:transparent;overflow:hidden;} svg{width:\(Int(pointSize))px;height:\(Int(pointSize))px;display:block;}</style>
        </head><body>\(svg)</body></html>
        """
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }
}
