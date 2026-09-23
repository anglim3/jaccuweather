import Foundation
import MapKit

/// CONUS NEXRAD via NWS WMS, same upstream family as Worker `/api/nws-wms`.
final class NWSRadarOverlay: MKTileOverlay {
    init() {
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: 256, height: 256)
        canReplaceMapContent = false
        minimumZ = 3
        maximumZ = 12
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let n = pow(2.0, Double(path.z))
        let origin = 20037508.342789244
        let res = (origin * 2) / n
        let minX = Double(path.x) * res - origin
        let maxY = origin - Double(path.y) * res
        let maxX = minX + res
        let minY = maxY - res
        var c = URLComponents(string: APIEndpoints.nwsWms)!
        c.queryItems = [
            URLQueryItem(name: "SERVICE", value: "WMS"),
            URLQueryItem(name: "VERSION", value: "1.3.0"),
            URLQueryItem(name: "REQUEST", value: "GetMap"),
            URLQueryItem(name: "LAYERS", value: "nexrad-n0q-wmst"),
            URLQueryItem(name: "STYLES", value: ""),
            URLQueryItem(name: "CRS", value: "EPSG:3857"),
            URLQueryItem(name: "BBOX", value: "\(minX),\(minY),\(maxX),\(maxY)"),
            URLQueryItem(name: "WIDTH", value: "256"),
            URLQueryItem(name: "HEIGHT", value: "256"),
            URLQueryItem(name: "FORMAT", value: "image/png"),
            URLQueryItem(name: "TRANSPARENT", value: "TRUE")
        ]
        return c.url!
    }
}
