import Foundation

/// One NOAA opengeo MRMS base-reflectivity mosaic. Bounds are CRS:84 (west, south, east, north).
struct NOAAMosaic: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let endpoint: URL
    let west: Double
    let south: Double
    let east: Double
    let north: Double

    var capabilitiesURL: URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "service", value: "WMS"),
            URLQueryItem(name: "version", value: "1.3.0"),
            URLQueryItem(name: "request", value: "GetCapabilities")
        ]
        return components.url!
    }

    func contains(latitude: Double, longitude: Double) -> Bool {
        let lon = Self.normalizeLongitude(longitude)
        return lon >= west && lon <= east && latitude >= south && latitude <= north
    }

    /// CONUS wins where it overlaps the Caribbean or Alaska. Outside every box, returns nil.
    static func containing(latitude: Double, longitude: Double) -> NOAAMosaic? {
        let lon = normalizeLongitude(longitude)
        if conus.contains(latitude: latitude, longitude: lon) { return conus }
        return [alaska, hawaii, caribbean, guam].first { $0.contains(latitude: latitude, longitude: lon) }
    }

    static func mosaic(id: String) -> NOAAMosaic? {
        all.first { $0.id == id }
    }

    static func normalizeLongitude(_ longitude: Double) -> Double {
        var lon = longitude.truncatingRemainder(dividingBy: 360)
        if lon > 180 { lon -= 360 }
        if lon < -180 { lon += 360 }
        return lon
    }

    static let conus = NOAAMosaic(
        id: "conus_bref_qcd",
        title: "CONUS",
        endpoint: URL(string: "https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows")!,
        west: -130, south: 20, east: -60, north: 55
    )
    static let alaska = NOAAMosaic(
        id: "alaska_bref_qcd",
        title: "Alaska",
        endpoint: URL(string: "https://opengeo.ncep.noaa.gov/geoserver/alaska/alaska_bref_qcd/ows")!,
        west: -176, south: 50, east: -126, north: 72
    )
    static let hawaii = NOAAMosaic(
        id: "hawaii_bref_qcd",
        title: "Hawaii",
        endpoint: URL(string: "https://opengeo.ncep.noaa.gov/geoserver/hawaii/hawaii_bref_qcd/ows")!,
        west: -164, south: 15, east: -151, north: 26
    )
    static let caribbean = NOAAMosaic(
        id: "carib_bref_qcd",
        title: "Caribbean",
        endpoint: URL(string: "https://opengeo.ncep.noaa.gov/geoserver/carib/carib_bref_qcd/ows")!,
        west: -90, south: 10, east: -60, north: 25
    )
    static let guam = NOAAMosaic(
        id: "guam_bref_qcd",
        title: "Guam",
        endpoint: URL(string: "https://opengeo.ncep.noaa.gov/geoserver/guam/guam_bref_qcd/ows")!,
        west: 140, south: 9, east: 150, north: 18
    )
    static let all = [conus, alaska, hawaii, caribbean, guam]
}

enum WebMercator {
    /// WGS84 sphere radius used by EPSG:3857, in meters.
    static let radius = 6_378_137.0
    static var halfExtent: Double { radius * Double.pi }

    static func forward(latitude: Double, longitude: Double) -> (x: Double, y: Double) {
        let lat = min(85.05112878, max(-85.05112878, latitude))
        let x = longitude * Double.pi / 180 * radius
        let latR = lat * Double.pi / 180
        let y = log(tan(Double.pi / 4 + latR / 2)) * radius
        return (x, y)
    }

    /// MKMapPoint is east from the antimeridian and south from the north pole.
    /// EPSG:3857 is easting and northing from the origin.
    static func epsg3857(mapX: Double, mapY: Double, worldWidth: Double) -> (x: Double, y: Double) {
        let span = halfExtent * 2
        let x = (mapX / worldWidth) * span - halfExtent
        let y = halfExtent - (mapY / worldWidth) * span
        return (x, y)
    }

    static func box(
        originX: Double,
        originY: Double,
        width: Double,
        height: Double,
        worldWidth: Double
    ) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let northwest = epsg3857(mapX: originX, mapY: originY, worldWidth: worldWidth)
        let southeast = epsg3857(mapX: originX + width, mapY: originY + height, worldWidth: worldWidth)
        return (
            min(northwest.x, southeast.x),
            min(northwest.y, southeast.y),
            max(northwest.x, southeast.x),
            max(northwest.y, southeast.y)
        )
    }
}

enum NOAAGetMap {
    /// WMS 1.3.0 GetMap on EPSG:3857. BBOX is minX,minY,maxX,maxY (easting, northing).
    /// `time` is a capabilities stamp passed through unchanged. Nil omits TIME.
    static func url(
        endpoint: URL,
        layer: String,
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double,
        width: Int,
        height: Int,
        time: String?
    ) -> URL? {
        let pixelsW = min(2048, max(1, width))
        let pixelsH = min(2048, max(1, height))
        func num(_ value: Double) -> String { String(format: "%.2f", value) }
        var query = [
            "SERVICE=WMS",
            "VERSION=1.3.0",
            "REQUEST=GetMap",
            "LAYERS=\(layer)",
            "STYLES=",
            "CRS=EPSG:3857",
            "BBOX=\(num(minX)),\(num(minY)),\(num(maxX)),\(num(maxY))",
            "WIDTH=\(pixelsW)",
            "HEIGHT=\(pixelsH)",
            "FORMAT=image/png",
            "TRANSPARENT=TRUE"
        ]
        if let time, !time.isEmpty {
            query.append("TIME=\(time)")
        }
        let base = endpoint.absoluteString
        let joiner = base.contains("?") ? "&" : "?"
        return URL(string: base + joiner + query.joined(separator: "&"))
    }
}

enum NOAATime {
    /// Values inside `<Dimension name="time">`, oldest first, unchanged.
    static func dimensionStamps(in xml: String) -> [String] {
        guard let name = xml.range(of: "name=\"time\"") else { return [] }
        let head = xml[..<name.lowerBound]
        guard let dimStart = head.range(of: "<Dimension", options: .backwards) else { return [] }
        guard head[dimStart.upperBound...].contains("<") == false else { return [] }
        guard let openEnd = xml[name.upperBound...].range(of: ">") else { return [] }
        guard let close = xml[openEnd.upperBound...].range(of: "</Dimension>") else { return [] }
        let body = xml[openEnd.upperBound..<close.lowerBound]
        return body
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.contains("T") }
    }

    /// Newest stamp, then every other stamp walking backward (~4 minutes). Oldest-first for the slider.
    static func playbackStamps(_ stamps: [String]) -> [String] {
        guard !stamps.isEmpty else { return [] }
        var chosen: [String] = []
        var index = stamps.count - 1
        while index >= 0 {
            chosen.append(stamps[index])
            index -= 2
        }
        return chosen.reversed()
    }

    static func date(from stamp: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: stamp) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: stamp)
    }
}

enum NOAARadarCatalog {
    struct Frame: Equatable, Identifiable, Sendable {
        let stamp: String
        let time: Date
        var id: String { stamp }
    }

    static func load(mosaic: NOAAMosaic, userAgent: String) async throws -> [Frame] {
        var request = URLRequest(url: mosaic.capabilitiesURL, timeoutInterval: 20)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let xml = String(data: data, encoding: .utf8) ?? ""
        let frames = frames(from: xml)
        if frames.isEmpty { throw URLError(.cannotParseResponse) }
        return frames
    }

    static func frames(from xml: String) -> [Frame] {
        NOAATime.playbackStamps(NOAATime.dimensionStamps(in: xml)).compactMap { stamp in
            guard let time = NOAATime.date(from: stamp) else { return nil }
            return Frame(stamp: stamp, time: time)
        }
    }
}
