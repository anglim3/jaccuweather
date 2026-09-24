import Foundation
import MapKit
import UIKit

/// Past radar frames from RainViewer's public Weather Maps API.
enum RainViewerCatalog {
    struct Frame: Equatable, Identifiable {
        let time: Date
        let path: String
        var id: String { path }
    }

    struct Maps: Equatable {
        let host: String
        let past: [Frame]
    }

    static func load() async throws -> Maps {
        var request = URLRequest(url: APIEndpoints.rainViewerMaps, timeoutInterval: 20)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(Secrets.openMeteoUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(Payload.self, from: data)
        let host = decoded.host.hasSuffix("/") ? String(decoded.host.dropLast()) : decoded.host
        let frames = decoded.radar.past.map { frame in
            let path = frame.path.hasPrefix("/") ? frame.path : "/" + frame.path
            return Frame(time: Date(timeIntervalSince1970: TimeInterval(frame.time)), path: path)
        }
        return Maps(host: host, past: frames)
    }

    /// `{host}{path}` with a single slash between them.
    static func framePrefix(host: String, path: String) -> String {
        let base = host.hasSuffix("/") ? String(host.dropLast()) : host
        let suffix = path.hasPrefix("/") ? path : "/" + path
        return base + suffix
    }

    private struct Payload: Decodable {
        let host: String
        let radar: Radar
        struct Radar: Decodable { let past: [Frame] }
        struct Frame: Decodable {
            let time: Int
            let path: String
        }
    }
}

/// Worldwide past-radar tiles. Native zoom stops at 7; deeper zooms crop that tile.
final class RainViewerRadarOverlay: MKTileOverlay {
    static let nativeMaxZoom = 7
    static let tilePixels = 256

    /// `host + path` from the weather-maps frame, no tile suffix.
    var framePrefix = ""

    /// Fired on the main queue with the prefix whose visible tiles just finished or failed.
    var onSettled: ((String) -> Void)?

    private let session: URLSession
    private let renderQueue = DispatchQueue(label: "cloud.janglim.jaccuweather.radar-tiles", qos: .userInitiated)
    private let lock = NSLock()
    private var generation = 0
    private var inflight = 0
    private var sawRequest = false
    private var settleAttempts = 0
    /// One download per parent URL. Child tiles at z>7 all crop this image.
    private var parentData: [URL: Data] = [:]
    private var parentWaiters: [URL: [(Data?) -> Void]] = [:]

    override init(urlTemplate: String?) {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 50 * 1024 * 1024
        )
        configuration.httpAdditionalHeaders = ["User-Agent": Secrets.openMeteoUserAgent]
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
        super.init(urlTemplate: urlTemplate)
        tileSize = CGSize(width: Self.tilePixels, height: Self.tilePixels)
        canReplaceMapContent = false
        minimumZ = 2
        // MapKit does not scale tiles past maximumZ, and the radar tab's ~1.2° span
        // asks for about z=10. Cap the server fetch at 7 and crop; see loadTile.
        maximumZ = 16
    }

    /// Call immediately before MapKit reloads tiles for a new frame.
    func armSettle() {
        lock.lock()
        generation += 1
        inflight = 0
        sawRequest = false
        settleAttempts = 0
        let generation = generation
        let prefix = framePrefix
        lock.unlock()
        scheduleIdleCheck(generation: generation, prefix: prefix)
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let zoom = min(path.z, Self.nativeMaxZoom)
        let scale = max(1, 1 << max(0, path.z - zoom))
        return Self.tileURL(prefix: framePrefix, z: zoom, x: path.x / scale, y: path.y / scale)
            ?? URL(string: "about:blank")!
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let prefix = framePrefix
        guard !prefix.isEmpty else {
            DispatchQueue.main.async { result(nil, URLError(.badURL)) }
            return
        }

        lock.lock()
        inflight += 1
        sawRequest = true
        let generation = generation
        lock.unlock()

        let zoom = min(path.z, Self.nativeMaxZoom)
        let scale = max(1, 1 << max(0, path.z - zoom))
        let screenScale = path.contentScaleFactor > 1 ? path.contentScaleFactor : 1
        guard let url = Self.tileURL(prefix: prefix, z: zoom, x: path.x / scale, y: path.y / scale) else {
            complete(result, generation: generation, prefix: prefix, data: nil, error: URLError(.badURL))
            return
        }

        loadParent(url) { [weak self] data in
            guard let self else {
                result(nil, URLError(.cancelled))
                return
            }
            self.renderQueue.async {
                let tile = Self.tileImage(data: data, path: path, scale: scale, screenScale: screenScale)
                DispatchQueue.main.async {
                    self.lock.lock()
                    let current = self.generation
                    self.lock.unlock()
                    if current == generation {
                        result(tile.data, tile.error)
                    } else {
                        result(nil, URLError(.cancelled))
                    }
                    self.completeSettle(generation: generation, prefix: prefix)
                }
            }
        }
    }

    /// Child tiles share one parent download. A 429 or timeout is retried so one
    /// burst during play/scrub does not leave a permanent blank square.
    private func loadParent(_ url: URL, completion: @escaping (Data?) -> Void) {
        lock.lock()
        if let cached = parentData[url] {
            lock.unlock()
            completion(cached)
            return
        }
        if parentWaiters[url] != nil {
            parentWaiters[url]?.append(completion)
            lock.unlock()
            return
        }
        parentWaiters[url] = [completion]
        lock.unlock()
        fetchParent(url, attemptsLeft: 3)
    }

    private func fetchParent(_ url: URL, attemptsLeft: Int) {
        session.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let ok = error == nil && (200...299).contains(status) && (data?.isEmpty == false)
            let retryable = !ok && attemptsLeft > 1 && (error != nil || status == 429 || status >= 500)
            if retryable {
                self.renderQueue.asyncAfter(deadline: .now() + .milliseconds(350 * (4 - attemptsLeft))) {
                    self.fetchParent(url, attemptsLeft: attemptsLeft - 1)
                }
                return
            }
            let prepared = ok ? data.flatMap(Self.opaqueEcho) : nil
            self.finishParent(url, data: prepared)
        }.resume()
    }

    private func finishParent(_ url: URL, data: Data?) {
        lock.lock()
        if let data {
            if parentData.count > 48 { parentData.removeAll() }
            parentData[url] = data
        }
        let waiters = parentWaiters.removeValue(forKey: url) ?? []
        lock.unlock()
        for waiter in waiters { waiter(data) }
    }

    private func complete(
        _ result: @escaping (Data?, Error?) -> Void,
        generation: Int,
        prefix: String,
        data: Data?,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            result(data, error)
            self?.completeSettle(generation: generation, prefix: prefix)
        }
    }

    private func completeSettle(generation: Int, prefix: String) {
        lock.lock()
        if generation == self.generation {
            inflight = max(0, inflight - 1)
        }
        let idle = generation == self.generation && inflight == 0 && sawRequest
        lock.unlock()
        guard idle else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.settleIfIdle(generation: generation, prefix: prefix)
        }
    }

    private func scheduleIdleCheck(generation: Int, prefix: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.settleIfIdle(generation: generation, prefix: prefix)
        }
    }

    /// MapKit may ask for tiles a turn after `reloadData`. Wait until that batch drains.
    private func settleIfIdle(generation: Int, prefix: String) {
        lock.lock()
        guard generation == self.generation else {
            lock.unlock()
            return
        }
        if inflight > 0 {
            lock.unlock()
            return
        }
        if sawRequest {
            lock.unlock()
            onSettled?(prefix)
            return
        }
        settleAttempts += 1
        let retry = settleAttempts < 8
        lock.unlock()
        if retry {
            scheduleIdleCheck(generation: generation, prefix: prefix)
        } else {
            onSettled?(prefix)
        }
    }

    static func tileURL(prefix: String, z: Int, x: Int, y: Int) -> URL? {
        let base = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        return URL(string: "\(base)/256/\(z)/\(x)/\(y)/2/1_0.png")
    }

    /// Light RainViewer echoes are tan pixels at alpha ~140–190. Under the renderer's
    /// 0.7 opacity they vanish into a green basemap, and a zoomed-in child tile of only
    /// that echo looks like a blank square. Keep the color, make the echo opaque.
    /// Fully clear pixels stay clear.
    static func opaqueEcho(_ data: Data) -> Data? {
        guard let source = UIImage(data: data)?.cgImage else { return nil }
        let width = source.width
        let height = source.height
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { _ in
            UIImage(cgImage: source).draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let cg = rendered.cgImage,
              cg.bitsPerPixel == 32,
              let src = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(src) else { return data }
        // UIGraphics bitmaps are little-endian premultiplied-first (BGRA in memory).
        let bytesPerRow = cg.bytesPerRow
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * bytesPerRow + x * 4
                let alpha = ptr[i + 3]
                if alpha == 0 || alpha == 255 {
                    buffer[i] = ptr[i]
                    buffer[i + 1] = ptr[i + 1]
                    buffer[i + 2] = ptr[i + 2]
                    buffer[i + 3] = alpha
                    continue
                }
                let scale = 255.0 / Double(alpha)
                buffer[i] = UInt8(min(255, Double(ptr[i]) * scale))
                buffer[i + 1] = UInt8(min(255, Double(ptr[i + 1]) * scale))
                buffer[i + 2] = UInt8(min(255, Double(ptr[i + 2]) * scale))
                buffer[i + 3] = 255
            }
        }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        let provider = CGDataProvider(data: Data(buffer) as CFData)
        guard let provider,
              let out = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ),
              let png = UIImage(cgImage: out).pngData() else { return data }
        return png
    }

    /// MapKit scales a native z≤7 PNG to the map. A deeper zoom, if one is still
    /// requested, crops that parent (XYZ y grows south, PNG y grows down).
    static func tileImage(
        data: Data?,
        path: MKTileOverlayPath,
        scale: Int,
        screenScale: CGFloat
    ) -> (data: Data?, error: Error?) {
        guard let data, !data.isEmpty, let image = UIImage(data: data), let cgImage = image.cgImage else {
            return (nil, URLError(.badServerResponse))
        }
        if scale <= 1 {
            return (data, nil)
        }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return (nil, URLError(.cannotDecodeContentData)) }
        let child = max(scale, 1)
        let subW = width / CGFloat(child)
        let subH = height / CGFloat(child)
        guard subW > 0, subH > 0 else { return (nil, URLError(.cannotDecodeContentData)) }
        let crop = CGRect(
            x: CGFloat(path.x % child) * subW,
            y: CGFloat(path.y % child) * subH,
            width: subW,
            height: subH
        )
        guard let png = fillTile(cgImage: cgImage, crop: crop, screenScale: max(screenScale, 1)) else {
            return (nil, URLError(.cannotDecodeContentData))
        }
        return (png, nil)
    }

    /// Draw `crop` (PNG y grows down, same as XYZ) into a full tile bitmap.
    /// Cut the parent with `CGImage` first so the child is that rectangle.
    static func fillTile(cgImage: CGImage, crop: CGRect, screenScale: CGFloat) -> Data? {
        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let integral = crop.integral.intersection(bounds)
        guard integral.width >= 1, integral.height >= 1, let cropped = cgImage.cropping(to: integral) else {
            return nil
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = screenScale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: tilePixels, height: tilePixels),
            format: format
        )
        let scaled = renderer.image { context in
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: CGFloat(tilePixels), height: CGFloat(tilePixels)))
        }
        return scaled.pngData()
    }
}
