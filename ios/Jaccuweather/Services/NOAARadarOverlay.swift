import Foundation
import MapKit
import UIKit

/// One WMS GetMap for the visible region. MapKit keeps it pinned to the ground;
/// a new frame or a settled pan replaces the image. Requests stay on EPSG:3857.
final class NOAAImageOverlay: NSObject, MKOverlay {
    var coordinate: CLLocationCoordinate2D
    var boundingMapRect: MKMapRect
    var image: CGImage?

    override init() {
        coordinate = CLLocationCoordinate2D(latitude: 39, longitude: -98)
        boundingMapRect = .null
        super.init()
    }
}

final class NOAAImageRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? NOAAImageOverlay,
              let image = overlay.image,
              overlay.boundingMapRect.intersects(mapRect) else { return }
        _ = zoomScale
        let rect = self.rect(for: overlay.boundingMapRect)
        guard rect.width > 1, rect.height > 1 else { return }
        context.saveGState()
        // Context y grows up; a north-up PNG has row 0 at the north edge.
        context.translateBy(x: rect.minX, y: rect.minY + rect.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        context.restoreGState()
    }
}

/// Loads NOAA frames for the map and redraws when the region or stamp changes.
final class NOAARadarLayer {
    let overlay = NOAAImageOverlay()
    var onSettled: ((String) -> Void)?

    private let session: URLSession
    private var mosaic: NOAAMosaic?
    private var stamp = ""
    private var token = ""
    private var active = false
    private var generation = 0
    private var task: URLSessionDataTask?
    private var retryWork: DispatchWorkItem?
    private var debounce: DispatchWorkItem?
    private var appliedKey = ""
    private var inFlightKey = ""
    private var pngCache: [String: Data] = [:]
    private var cacheOrder: [String] = []
    private weak var mapView: MKMapView?

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 80 * 1024 * 1024
        )
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    func activate(mosaic: NOAAMosaic, stamp: String, token: String, map: MKMapView) {
        let changed = !active || self.mosaic != mosaic || self.stamp != stamp
        active = true
        self.mosaic = mosaic
        self.stamp = stamp
        self.token = token
        mapView = map
        if changed {
            appliedKey = ""
            fetchNow()
        }
    }

    func deactivate(on map: MKMapView?) {
        active = false
        generation += 1
        task?.cancel()
        task = nil
        debounce?.cancel()
        retryWork?.cancel()
        inFlightKey = ""
        appliedKey = ""
        if let map, map.overlays.contains(where: { ($0 as AnyObject) === overlay }) {
            map.removeOverlay(overlay)
        }
    }

    /// Call from `regionDidChange`. A pan keeps the previous image geolocked until this fires.
    func regionDidChange() {
        guard active else { return }
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.fetchNow()
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func fetchNow() {
        guard active, let mosaic, !stamp.isEmpty, let map = mapView else { return }
        guard map.bounds.width > 2, map.bounds.height > 2 else { return }
        let region = map.region
        guard region.span.latitudeDelta > 0.02, region.span.latitudeDelta < 40,
              region.span.longitudeDelta > 0.02, region.span.longitudeDelta < 40 else { return }
        let rect = Self.quantized(map.visibleMapRect)
        guard rect.size.width > 1, rect.size.height > 1 else { return }
        let pixels = Self.pixelSize(bounds: map.bounds, scale: map.traitCollection.displayScale)
        let world = MKMapSize.world.width
        let box = WebMercator.box(
            originX: rect.origin.x,
            originY: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height,
            worldWidth: world
        )
        guard let url = NOAAGetMap.url(
            endpoint: mosaic.endpoint,
            layer: mosaic.id,
            minX: box.minX,
            minY: box.minY,
            maxX: box.maxX,
            maxY: box.maxY,
            width: pixels.width,
            height: pixels.height,
            time: stamp
        ) else { return }

        let key = url.absoluteString
        let token = token
        if key == appliedKey {
            onSettled?(token)
            return
        }
        if key == inFlightKey { return }

        generation += 1
        let generation = generation
        task?.cancel()
        retryWork?.cancel()
        inFlightKey = ""
        if let cached = pngCache[key], let image = Self.cgImage(from: cached) {
            apply(image: image, rect: rect, on: map)
            appliedKey = key
            onSettled?(token)
            return
        }

        inFlightKey = key
        startRequest(
            url: url,
            key: key,
            rect: rect,
            token: token,
            generation: generation,
            allowRetry: true
        )
    }

    private func startRequest(
        url: URL,
        key: String,
        rect: MKMapRect,
        token: String,
        generation: Int,
        allowRetry: Bool
    ) {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(Secrets.nwsUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/png", forHTTPHeaderField: "Accept")
        task = session.dataTask(with: request) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let cancelled = (error as? URLError)?.code == .cancelled
            let png = data.flatMap(Self.pngData)
            let ok = !cancelled && error == nil && (200...299).contains(status) && png != nil
            DispatchQueue.main.async {
                guard let self, generation == self.generation, self.active else { return }
                if cancelled { return }
                let retryable = !ok && allowRetry && (error != nil || status == 429 || status >= 500)
                if retryable {
                    let work = DispatchWorkItem { [weak self] in
                        guard let self, generation == self.generation, self.active else { return }
                        self.startRequest(
                            url: url,
                            key: key,
                            rect: rect,
                            token: token,
                            generation: generation,
                            allowRetry: false
                        )
                    }
                    self.retryWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
                    return
                }
                self.inFlightKey = ""
                if let png, let image = Self.cgImage(from: png), let map = self.mapView {
                    self.storeCache(key, data: png)
                    self.apply(image: image, rect: rect, on: map)
                    self.appliedKey = key
                }
                self.onSettled?(token)
            }
        }
        task?.resume()
    }

    private func apply(image: CGImage, rect: MKMapRect, on map: MKMapView) {
        let previous = overlay.boundingMapRect
        let sameRect = previous.size.width > 1
            && abs(previous.origin.x - rect.origin.x) < 0.5
            && abs(previous.origin.y - rect.origin.y) < 0.5
            && abs(previous.size.width - rect.size.width) < 0.5
            && abs(previous.size.height - rect.size.height) < 0.5
        overlay.image = image
        overlay.boundingMapRect = rect
        overlay.coordinate = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        let listed = map.overlays.contains { ($0 as AnyObject) === overlay }
        if listed && sameRect {
            if let renderer = map.renderer(for: overlay) {
                renderer.setNeedsDisplay()
            }
            return
        }
        if listed { map.removeOverlay(overlay) }
        map.addOverlay(overlay, level: .aboveRoads)
    }

    private func storeCache(_ key: String, data: Data) {
        if pngCache[key] == nil { cacheOrder.append(key) }
        pngCache[key] = data
        while cacheOrder.count > 24 {
            let oldest = cacheOrder.removeFirst()
            pngCache.removeValue(forKey: oldest)
        }
    }

    /// Snap the visible rect to a few meters so a second layout pass reuses the image.
    static func quantized(_ rect: MKMapRect) -> MKMapRect {
        let step = 128.0
        let x = floor(rect.origin.x / step) * step
        let y = floor(rect.origin.y / step) * step
        let maxX = ceil(rect.maxX / step) * step
        let maxY = ceil(rect.maxY / step) * step
        return MKMapRect(x: x, y: y, width: max(maxX - x, step), height: max(maxY - y, step))
    }

    static func pixelSize(bounds: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        let screen = scale > 1 ? min(scale, 2) : 1
        var width = Int((bounds.width * screen).rounded())
        var height = Int((bounds.height * screen).rounded())
        let cap = 1024
        let longest = max(width, height, 1)
        if longest > cap {
            let factor = Double(cap) / Double(longest)
            width = Int((Double(width) * factor).rounded())
            height = Int((Double(height) * factor).rounded())
        }
        return (max(width, 64), max(height, 64))
    }

    static func pngData(_ data: Data) -> Data? {
        guard data.count > 8 else { return nil }
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard Array(data.prefix(8)) == signature else { return nil }
        return data
    }

    static func cgImage(from data: Data) -> CGImage? {
        UIImage(data: data)?.cgImage
    }
}
