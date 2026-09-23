import SwiftUI
import MapKit
import WebKit

struct RadarView: View {
    @Environment(WeatherViewModel.self) private var model
    @State private var showVentusky = false
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $camera) {
                Marker(model.locationName, coordinate: model.coordinate)
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 10) {
                Text("Native MapKit is the default radar surface. Ventusky stays an optional web embed (same URL as the website iframe), not the app shell.")
                    .font(.caption)
                    .foregroundStyle(JWTheme.muted)
                HStack {
                    Button("Embed Ventusky") { showVentusky = true }
                        .buttonStyle(.borderedProminent)
                    Link("Open in Safari", destination: APIEndpoints.ventusky(latitude: model.coordinate.latitude, longitude: model.coordinate.longitude))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JWTheme.background)
        }
        .background(JWTheme.background.ignoresSafeArea())
        .navigationTitle("Radar")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { recenter() }
        .onChange(of: model.coordinate.latitude) { _, _ in recenter() }
        .sheet(isPresented: $showVentusky) {
            NavigationStack {
                VentuskyWebView(url: APIEndpoints.ventusky(latitude: model.coordinate.latitude, longitude: model.coordinate.longitude))
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Ventusky")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showVentusky = false }
                        }
                    }
            }
        }
    }

    private func recenter() {
        camera = .region(MKCoordinateRegion(
            center: model.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
        ))
    }
}

struct VentuskyWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.scrollView.bounces = false
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }
}
