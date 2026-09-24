import SwiftUI
import MapKit
import CoreLocation

struct RadarView: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var host = ""
    @State private var frames: [RainViewerCatalog.Frame] = []
    @State private var frameIndex = 0
    @State private var playing = false
    @State private var tilesSettled = false
    @State private var loadError: String?
    @State private var playTask: Task<Void, Never>?

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    private var framePrefix: String {
        guard frames.indices.contains(frameIndex), !host.isEmpty else { return "" }
        return RainViewerCatalog.framePrefix(host: host, path: frames[frameIndex].path)
    }

    var body: some View {
        VStack(spacing: 0) {
            RadarMapView(
                coordinate: model.coordinate,
                title: model.locationName,
                framePrefix: framePrefix,
                onTilesSettled: { prefix in
                    if prefix == framePrefix { tilesSettled = true }
                }
            )
            .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Button {
                        setPlaying(!playing)
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(theme.text)
                            .frame(width: 36, height: 36)
                            .background(theme.tile, in: Circle())
                            .overlay(Circle().stroke(theme.cardStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(frames.count < 2)
                    .accessibilityLabel(playing ? "Pause radar" : "Play radar")

                    if frames.count > 1 {
                        Slider(
                            value: Binding(
                                get: { Double(frameIndex) },
                                set: { newValue in
                                    setPlaying(false)
                                    selectFrame(Int(newValue.rounded()))
                                }
                            ),
                            in: 0...Double(frames.count - 1),
                            step: 1
                        )
                        .tint(theme.accent)
                        .accessibilityLabel("Radar time")
                    } else {
                        Text(frames.isEmpty ? (loadError ?? "Loading radar…") : "One radar frame")
                            .font(.caption)
                            .foregroundStyle(theme.muted)
                    }
                }

                Text(timeLabel)
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(theme.text)

                Link(destination: APIEndpoints.rainViewerCredit) {
                    Text("Radar from RainViewer")
                        .font(.caption)
                        .foregroundStyle(theme.accent)
                }
                .accessibilityLabel("Radar from RainViewer")
            }
            .padding(16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card)
            .overlay(alignment: .top) {
                Rectangle().fill(theme.cardStroke).frame(height: 1)
            }
        }
        .safeAreaPadding(.bottom, 4)
        .background {
            theme.background.ignoresSafeArea()
        }
        .navigationTitle("Radar")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshLoop() }
        .onDisappear { setPlaying(false) }
    }

    private var timeLabel: String {
        guard frames.indices.contains(frameIndex) else {
            return loadError ?? "Loading radar…"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(secondsFromGMT: model.weather?.utcOffset ?? 0)
        formatter.setLocalizedDateFormatFromTemplate("EEE h:mm a")
        return formatter.string(from: frames[frameIndex].time)
    }

    private func refreshLoop() async {
        await refreshFrames()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            if Task.isCancelled { return }
            await refreshFrames()
        }
    }

    private func refreshFrames() async {
        do {
            let maps = try await RainViewerCatalog.load()
            let wasLatest = frames.isEmpty || frameIndex >= frames.count - 1
            let previous = frames.indices.contains(frameIndex) ? frames[frameIndex].path : nil
            let oldPrefix = framePrefix
            host = maps.host
            frames = maps.past
            if wasLatest {
                frameIndex = max(frames.count - 1, 0)
            } else if let previous, let kept = frames.firstIndex(where: { $0.path == previous }) {
                frameIndex = kept
            } else {
                frameIndex = max(frames.count - 1, 0)
            }
            if framePrefix != oldPrefix { tilesSettled = false }
            loadError = frames.isEmpty ? "No radar frames" : nil
            if frames.count < 2 { setPlaying(false) }
        } catch {
            if frames.isEmpty { loadError = "Radar frames unavailable" }
        }
    }

    private func selectFrame(_ index: Int) {
        guard frames.indices.contains(index), index != frameIndex else { return }
        tilesSettled = false
        frameIndex = index
    }

    private func setPlaying(_ on: Bool) {
        playTask?.cancel()
        playTask = nil
        guard on, frames.count > 1 else {
            playing = false
            return
        }
        playing = true
        playTask = Task { await runPlayback() }
    }

    private func runPlayback() async {
        while !Task.isCancelled && playing && frames.count > 1 {
            let shownAt = Date()
            while !Task.isCancelled && playing && !tilesSettled && Date().timeIntervalSince(shownAt) < 4 {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            let remain = 0.85 - Date().timeIntervalSince(shownAt)
            if remain > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remain * 1_000_000_000))
            }
            guard !Task.isCancelled, playing, frames.count > 1 else { return }
            selectFrame((frameIndex + 1) % frames.count)
            await Task.yield()
        }
    }
}

struct RadarMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let title: String
    let framePrefix: String
    let onTilesSettled: (String) -> Void

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.overlay.onSettled = { [weak coordinator] prefix in
            coordinator?.onSettled?(prefix)
        }
        return coordinator
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSettled = onTilesSettled

        let moved = coordinator.lastCoordinate.map { previous in
            abs(previous.latitude - coordinate.latitude) > 0.00001
                || abs(previous.longitude - coordinate.longitude) > 0.00001
        } ?? true
        if moved {
            map.setRegion(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
                ),
                animated: false
            )
            coordinator.lastCoordinate = coordinate
        }
        if moved || coordinator.lastTitle != title {
            map.removeAnnotations(map.annotations)
            let pin = MKPointAnnotation()
            pin.coordinate = coordinate
            pin.title = title
            map.addAnnotation(pin)
            coordinator.lastTitle = title
        }

        guard !framePrefix.isEmpty else { return }
        let prefixChanged = coordinator.appliedPrefix != framePrefix
        let alreadyAdded = map.overlays.contains { ($0 as AnyObject) === coordinator.overlay }
        if prefixChanged {
            coordinator.overlay.framePrefix = framePrefix
            coordinator.appliedPrefix = framePrefix
            coordinator.overlay.armSettle()
        }
        if !alreadyAdded {
            map.addOverlay(coordinator.overlay, level: .aboveRoads)
        } else if prefixChanged {
            coordinator.renderer?.reloadData()
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let overlay = RainViewerRadarOverlay(urlTemplate: nil)
        var renderer: MKTileOverlayRenderer?
        var onSettled: ((String) -> Void)?
        var lastCoordinate: CLLocationCoordinate2D?
        var lastTitle: String?
        var appliedPrefix = ""

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tile = overlay as? RainViewerRadarOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            if let renderer, renderer.overlay === tile {
                return renderer
            }
            let created = MKTileOverlayRenderer(tileOverlay: tile)
            created.alpha = 0.7
            renderer = created
            return created
        }
    }
}
