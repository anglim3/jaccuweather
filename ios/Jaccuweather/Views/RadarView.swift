import SwiftUI
import MapKit
import CoreLocation

struct RadarView: View {
    @Environment(WeatherViewModel.self) private var model
    @State private var showNWS = true

    var body: some View {
        VStack(spacing: 0) {
            RadarMapView(
                coordinate: model.coordinate,
                title: model.locationName,
                showNWS: showNWS
            )
            .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("NWS radar overlay (CONUS)", isOn: $showNWS)
                Text("Ventusky is a Safari link-out — same public URL the website uses after lockdown strips the HTML proxy. WKWebView is not used.")
                    .font(.caption)
                    .foregroundStyle(JWTheme.muted)
                Link("Open Ventusky radar", destination: APIEndpoints.ventusky(latitude: model.coordinate.latitude, longitude: model.coordinate.longitude))
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JWTheme.background)
        }
        .background(JWTheme.background.ignoresSafeArea())
        .navigationTitle("Radar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RadarMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let title: String
    let showNWS: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.setRegion(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)), animated: false)
        map.removeAnnotations(map.annotations)
        let pin = MKPointAnnotation()
        pin.coordinate = coordinate
        pin.title = title
        map.addAnnotation(pin)

        let hasOverlay = map.overlays.contains { $0 is NWSRadarOverlay }
        if showNWS && !hasOverlay {
            map.addOverlay(NWSRadarOverlay(), level: .aboveRoads)
        } else if !showNWS {
            map.removeOverlays(map.overlays.filter { $0 is NWSRadarOverlay })
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tile)
                renderer.alpha = 0.7
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
