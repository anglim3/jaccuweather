import Foundation
import MapKit

@main
struct NOAAMrmsCheck {
    static func main() {
        run()
    }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL \(message)\n", stderr)
        exit(1)
    }
}

func checkMosaic(_ name: String, _ mosaic: NOAAMosaic?, _ id: String) {
    check(mosaic?.id == id, "\(name) expected \(id), got \(mosaic?.id ?? "nil")")
}

func run() {
checkMosaic("Miami", NOAAMosaic.containing(latitude: 25.76, longitude: -80.19), "conus_bref_qcd")
checkMosaic("Seattle", NOAAMosaic.containing(latitude: 47.61, longitude: -122.33), "conus_bref_qcd")
checkMosaic("overlap CONUS/Caribbean", NOAAMosaic.containing(latitude: 22, longitude: -70), "conus_bref_qcd")
checkMosaic("overlap CONUS/Alaska", NOAAMosaic.containing(latitude: 52, longitude: -128), "conus_bref_qcd")
checkMosaic("San Juan", NOAAMosaic.containing(latitude: 18.47, longitude: -66.11), "carib_bref_qcd")
checkMosaic("Honolulu", NOAAMosaic.containing(latitude: 21.31, longitude: -157.86), "hawaii_bref_qcd")
checkMosaic("Anchorage", NOAAMosaic.containing(latitude: 61.22, longitude: -149.90), "alaska_bref_qcd")
checkMosaic("Alaska north of CONUS", NOAAMosaic.containing(latitude: 60, longitude: -128), "alaska_bref_qcd")
checkMosaic("Guam", NOAAMosaic.containing(latitude: 13.48, longitude: 144.75), "guam_bref_qcd")
checkMosaic("Guam wrapped", NOAAMosaic.containing(latitude: 13.48, longitude: 144.75 - 360), "guam_bref_qcd")
check(NOAAMosaic.containing(latitude: 51.51, longitude: -0.13) == nil, "London should be outside NOAA")
check(NOAAMosaic.containing(latitude: 35.68, longitude: 139.69) == nil, "Tokyo should be outside NOAA")
check(NOAAMosaic.containing(latitude: -33.87, longitude: 151.21) == nil, "Sydney should be outside NOAA")

let origin = WebMercator.forward(latitude: 0, longitude: 0)
check(abs(origin.x) < 0.01 && abs(origin.y) < 0.01, "equator/prime meridian is the EPSG:3857 origin")

let seattle = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
let mapPoint = MKMapPoint(seattle)
let projected = WebMercator.epsg3857(
    mapX: mapPoint.x,
    mapY: mapPoint.y,
    worldWidth: MKMapSize.world.width
)
let expected = WebMercator.forward(latitude: seattle.latitude, longitude: seattle.longitude)
check(abs(projected.x - expected.x) < 2, "map x \(projected.x) vs \(expected.x)")
check(abs(projected.y - expected.y) < 2, "map y \(projected.y) vs \(expected.y)")

let box = WebMercator.box(
    originX: mapPoint.x,
    originY: mapPoint.y,
    width: 10_000,
    height: 8_000,
    worldWidth: MKMapSize.world.width
)
check(box.minX < box.maxX && box.minY < box.maxY, "bbox is ordered min,max")
check(abs(box.maxX - box.minX) > 100 && abs(box.maxY - box.minY) > 100, "bbox has extent")

let url = NOAAGetMap.url(
    endpoint: NOAAMosaic.conus.endpoint,
    layer: NOAAMosaic.conus.id,
    minX: box.minX,
    minY: box.minY,
    maxX: box.maxX,
    maxY: box.maxY,
    width: 800,
    height: 600,
    time: "2026-09-25T07:04:13.000Z"
)
check(url != nil, "GetMap URL")
let absolute = url!.absoluteString
check(absolute.contains("CRS=EPSG:3857"), absolute)
check(!absolute.contains("EPSG:4326"), absolute)
check(absolute.contains("LAYERS=conus_bref_qcd"), absolute)
check(absolute.contains("STYLES="), absolute)
check(absolute.contains("TRANSPARENT=TRUE"), absolute)
check(absolute.contains("TIME=2026-09-25T07:04:13.000Z"), absolute)
check(absolute.contains("VERSION=1.3.0"), absolute)
let bbox = absolute.split(separator: "&").first { $0.hasPrefix("BBOX=") }!
let parts = bbox.dropFirst("BBOX=".count).split(separator: ",").map { Double($0)! }
check(parts.count == 4, "bbox parts")
check(parts[0] < parts[2] && parts[1] < parts[3], "bbox axis order minX,minY,maxX,maxY")

let xml = """
<Dimension name="time" default="2026-09-25T07:04:13Z" units="ISO8601" nearestValue="1">2026-09-25T05:06:14.000Z,2026-09-25T05:08:16.000Z,2026-09-25T05:10:13.000Z,2026-09-25T07:04:13.000Z</Dimension>
"""
let stamps = NOAATime.dimensionStamps(in: xml)
check(stamps.count == 4, "stamp count \(stamps.count)")
check(stamps.last == "2026-09-25T07:04:13.000Z", "newest stamp")
let playback = NOAATime.playbackStamps(stamps)
check(playback == ["2026-09-25T05:08:16.000Z", "2026-09-25T07:04:13.000Z"], "playback \(playback)")
let frames = NOAARadarCatalog.frames(from: xml)
check(frames.count == 2, "frame count")
check(frames.last?.stamp == "2026-09-25T07:04:13.000Z", "latest frame kept")
check(NOAATime.date(from: frames[0].stamp) != nil, "stamp date")

let sixty = (0..<60).map { String(format: "2026-09-25T05:%02d:00.000Z", $0 % 60) }
let thinned = NOAATime.playbackStamps(sixty)
check(thinned.count == 30, "sixty stamps thin to \(thinned.count)")
check(thinned.last == sixty.last, "newest of sixty kept")

fputs("ok\n", stdout)
}
