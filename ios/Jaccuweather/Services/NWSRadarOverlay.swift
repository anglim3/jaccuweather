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
    private let lock = NSLock()
    private var generation = 0
    private var inflight = 0
    private var sawRequest = false
    private var settleAttempts = 0

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
        guard let url = Self.tileURL(prefix: prefix, z: zoom, x: path.x / scale, y: path.y / scale) else {
            complete(result, generation: generation, prefix: prefix, data: nil, error: URLError(.badURL))
            return
        }

        session.dataTask(with: url) { [weak self] data, response, error in
            let tile = Self.tileData(data: data, response: response, error: error, path: path, scale: scale)
            DispatchQueue.main.async {
                guard let self else {
                    result(nil, URLError(.cancelled))
                    return
                }
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
        }.resume()
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

    /// Crop the z=7 parent so a pinched-in tile is that quadrant, scaled back to 256.
    static func tileData(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        path: MKTileOverlayPath,
        scale: Int
    ) -> (data: Data?, error: Error?) {
        if let error { return (nil, error) }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let data, !data.isEmpty else {
            return (nil, URLError(.badServerResponse))
        }
        guard scale > 1 else { return (data, nil) }
        guard let cropped = cropParentTile(data, path: path, scale: scale) else {
            return (nil, URLError(.cannotDecodeContentData))
        }
        return (cropped, nil)
    }

    static func cropParentTile(_ data: Data, path: MKTileOverlayPath, scale: Int) -> Data? {
        guard scale > 1, let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return nil }
        let subW = width / CGFloat(scale)
        let subH = height / CGFloat(scale)
        guard subW > 0, subH > 0 else { return nil }
        let crop = CGRect(
            x: CGFloat(path.x % scale) * subW,
            y: CGFloat(path.y % scale) * subH,
            width: subW,
            height: subH
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: tilePixels, height: tilePixels),
            format: format
        )
        let factorX = CGFloat(tilePixels) / subW
        let factorY = CGFloat(tilePixels) / subH
        let scaled = renderer.image { context in
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage: cgImage).draw(in: CGRect(
                x: -crop.origin.x * factorX,
                y: -crop.origin.y * factorY,
                width: width * factorX,
                height: height * factorY
            ))
        }
        return scaled.pngData()
    }
}
