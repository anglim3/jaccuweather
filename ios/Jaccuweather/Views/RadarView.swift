import SwiftUI
import MapKit
import CoreLocation

private enum RadarSource: String {
    case rainViewer
    case noaa
}

struct RadarView: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    var isActive = true
    @State private var source: RadarSource = .rainViewer
    @State private var host = ""
    @State private var frames: [RainViewerCatalog.Frame] = []
    @State private var noaaFrames: [NOAARadarCatalog.Frame] = []
    @State private var rainIndex = 0
    @State private var noaaIndex = 0
    @State private var playing = false
    @State private var tilesSettled = false
    @State private var loadError: String?
    @State private var noaaError: String?
    @State private var playTask: Task<Void, Never>?

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    private var mosaic: NOAAMosaic? {
        NOAAMosaic.containing(latitude: model.coordinate.latitude, longitude: model.coordinate.longitude)
    }

    private var showingNOAA: Bool { source == .noaa && mosaic != nil }

    private var framePrefix: String {
        guard frames.indices.contains(rainIndex), !host.isEmpty else { return "" }
        return RainViewerCatalog.framePrefix(host: host, path: frames[rainIndex].path)
    }

    private var settleToken: String {
        if showingNOAA {
            guard let mosaic, noaaFrames.indices.contains(noaaIndex) else { return "" }
            return "noaa|\(mosaic.id)|\(noaaFrames[noaaIndex].stamp)"
        }
        return framePrefix
    }

    private var mapLayer: RadarMapView.Layer {
        if showingNOAA {
            guard let mosaic, noaaFrames.indices.contains(noaaIndex) else { return .empty }
            let frame = noaaFrames[noaaIndex]
            return .noaa(
                mosaicID: mosaic.id,
                stamp: frame.stamp,
                token: "noaa|\(mosaic.id)|\(frame.stamp)"
            )
        }
        if framePrefix.isEmpty { return .empty }
        return .rain(prefix: framePrefix)
    }

    private var activeCount: Int { showingNOAA ? noaaFrames.count : frames.count }

    private var frameIndex: Int { showingNOAA ? noaaIndex : rainIndex }

    var body: some View {
        VStack(spacing: 0) {
            RadarMapView(
                coordinate: model.coordinate,
                title: model.locationName,
                layer: mapLayer,
                onTilesSettled: { token in
                    if token == settleToken { tilesSettled = true }
                }
            )
            .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 10) {
                if mosaic != nil {
                    sourceSwitch
                }

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
                    .disabled(activeCount < 2)
                    .accessibilityLabel(playing ? "Pause radar" : "Play radar")

                    if activeCount > 1 {
                        Slider(
                            value: Binding(
                                get: { Double(frameIndex) },
                                set: { newValue in
                                    setPlaying(false)
                                    selectFrame(Int(newValue.rounded()))
                                }
                            ),
                            in: 0...Double(activeCount - 1),
                            step: 1
                        )
                        .tint(theme.accent)
                        .accessibilityLabel("Radar time")
                    } else {
                        Text(statusLine)
                            .font(.caption)
                            .foregroundStyle(theme.muted)
                    }
                }

                Text(timeLabel)
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(theme.text)

                if showingNOAA {
                    Link(destination: APIEndpoints.noaaRadarCredit) {
                        Text("NOAA / NWS MRMS")
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                    }
                    .accessibilityLabel("NOAA / NWS MRMS")
                } else {
                    Link(destination: APIEndpoints.rainViewerCredit) {
                        Text("Radar from RainViewer")
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                    }
                    .accessibilityLabel("Radar from RainViewer")
                }

                if mosaic == nil {
                    Text("US (NOAA) radar covers the mainland, Alaska, Hawaii, the Caribbean, and Guam.")
                        .font(.caption)
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        .onChange(of: isActive) { _, active in
            if active {
                Task {
                    await refreshFrames()
                    await refreshNOAA(resetToLatest: false)
                }
            } else {
                setPlaying(false)
            }
        }
        .onChange(of: mosaic?.id) { old, new in
            guard old != new else { return }
            if new == nil {
                noaaFrames = []
                noaaError = nil
                if source == .noaa {
                    setPlaying(false)
                    source = .rainViewer
                    tilesSettled = false
                }
                return
            }
            Task { await refreshNOAA(resetToLatest: true) }
        }
        .onDisappear { setPlaying(false) }
    }

    private var sourceSwitch: some View {
        HStack(spacing: 8) {
            sourceChip("Global (RainViewer)", value: .rainViewer)
            sourceChip("US (NOAA)", value: .noaa)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Radar source")
    }

    private func sourceChip(_ title: String, value: RadarSource) -> some View {
        let selected = source == value
        return Button {
            selectSource(value)
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? Color(red: 13 / 255, green: 33 / 255, blue: 55 / 255) : theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    selected ? theme.accent : theme.tile,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var statusLine: String {
        if showingNOAA {
            if noaaFrames.isEmpty { return noaaError ?? "Loading radar…" }
            return "One radar frame"
        }
        return frames.isEmpty ? (loadError ?? "Loading radar…") : "One radar frame"
    }

    private var timeLabel: String {
        let formatter = Self.timeFormatter(utcOffset: model.weather?.utcOffset ?? 0)
        if showingNOAA {
            guard noaaFrames.indices.contains(noaaIndex) else {
                return noaaError ?? "Loading radar…"
            }
            return formatter.string(from: noaaFrames[noaaIndex].time)
        }
        guard frames.indices.contains(rainIndex) else {
            return loadError ?? "Loading radar…"
        }
        return formatter.string(from: frames[rainIndex].time)
    }

    private static func timeFormatter(utcOffset: Int) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(secondsFromGMT: utcOffset)
        formatter.setLocalizedDateFormatFromTemplate("EEE h:mm a")
        return formatter
    }

    private func refreshLoop() async {
        await refreshFrames()
        await refreshNOAA(resetToLatest: false)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            if Task.isCancelled { return }
            if isActive {
                await refreshFrames()
                await refreshNOAA(resetToLatest: false)
            }
        }
    }

    private func refreshFrames() async {
        do {
            let maps = try await RainViewerCatalog.load()
            let wasLatest = frames.isEmpty || rainIndex >= frames.count - 1
            let previous = frames.indices.contains(rainIndex) ? frames[rainIndex].path : nil
            let oldToken = settleToken
            host = maps.host
            frames = maps.past
            if wasLatest {
                rainIndex = max(frames.count - 1, 0)
            } else if let previous, let kept = frames.firstIndex(where: { $0.path == previous }) {
                rainIndex = kept
            } else {
                rainIndex = max(frames.count - 1, 0)
            }
            if !showingNOAA, settleToken != oldToken { tilesSettled = false }
            loadError = frames.isEmpty ? "No radar frames" : nil
            if !showingNOAA, frames.count < 2 { setPlaying(false) }
        } catch {
            if frames.isEmpty { loadError = "Radar frames unavailable" }
        }
    }

    private func refreshNOAA(resetToLatest: Bool) async {
        guard let mosaic else { return }
        let requested = mosaic.id
        do {
            let loaded = try await NOAARadarCatalog.load(mosaic: mosaic, userAgent: Secrets.nwsUserAgent)
            guard self.mosaic?.id == requested else { return }
            let wasLatest = noaaFrames.isEmpty || noaaIndex >= noaaFrames.count - 1
            let previous = noaaFrames.indices.contains(noaaIndex) ? noaaFrames[noaaIndex].stamp : nil
            let oldToken = settleToken
            noaaFrames = loaded
            if resetToLatest || wasLatest {
                noaaIndex = max(loaded.count - 1, 0)
            } else if let previous, let kept = loaded.firstIndex(where: { $0.stamp == previous }) {
                noaaIndex = kept
            } else {
                noaaIndex = max(loaded.count - 1, 0)
            }
            if showingNOAA, settleToken != oldToken { tilesSettled = false }
            noaaError = loaded.isEmpty ? "NOAA radar unavailable" : nil
            if showingNOAA, loaded.count < 2 { setPlaying(false) }
        } catch {
            if noaaFrames.isEmpty { noaaError = "NOAA radar unavailable" }
        }
    }

    private func selectSource(_ newSource: RadarSource) {
        guard newSource != source else { return }
        setPlaying(false)
        source = newSource
        tilesSettled = false
    }

    private func selectFrame(_ index: Int) {
        if showingNOAA {
            guard noaaFrames.indices.contains(index), index != noaaIndex else { return }
            tilesSettled = false
            noaaIndex = index
        } else {
            guard frames.indices.contains(index), index != rainIndex else { return }
            tilesSettled = false
            rainIndex = index
        }
    }

    private func setPlaying(_ on: Bool) {
        playTask?.cancel()
        playTask = nil
        guard on, activeCount > 1 else {
            playing = false
            return
        }
        playing = true
        playTask = Task { await runPlayback() }
    }

    private func runPlayback() async {
        while !Task.isCancelled && playing && activeCount > 1 {
            let shownAt = Date()
            while !Task.isCancelled && playing && !tilesSettled && Date().timeIntervalSince(shownAt) < 4 {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            let remain = 0.85 - Date().timeIntervalSince(shownAt)
            if remain > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remain * 1_000_000_000))
            }
            guard !Task.isCancelled, playing, activeCount > 1 else { return }
            selectFrame((frameIndex + 1) % activeCount)
            await Task.yield()
        }
    }
}

struct RadarMapView: UIViewRepresentable {
    enum Layer: Equatable {
        case empty
        case rain(prefix: String)
        case noaa(mosaicID: String, stamp: String, token: String)
    }

    let coordinate: CLLocationCoordinate2D
    let title: String
    let layer: Layer
    let onTilesSettled: (String) -> Void

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.overlay.onSettled = { [weak coordinator] prefix in
            coordinator?.onSettled?(prefix)
        }
        coordinator.noaa.onSettled = { [weak coordinator] token in
            coordinator?.onSettled?(token)
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

        switch layer {
        case .empty:
            coordinator.noaa.deactivate(on: map)
            removeRain(from: map, coordinator: coordinator)
        case .rain(let prefix):
            coordinator.noaa.deactivate(on: map)
            applyRain(prefix, map: map, coordinator: coordinator)
        case .noaa(let mosaicID, let stamp, let token):
            removeRain(from: map, coordinator: coordinator)
            if let mosaic = NOAAMosaic.mosaic(id: mosaicID) {
                coordinator.noaa.activate(mosaic: mosaic, stamp: stamp, token: token, map: map)
            } else {
                coordinator.noaa.deactivate(on: map)
            }
        }
    }

    private func removeRain(from map: MKMapView, coordinator: Coordinator) {
        if map.overlays.contains(where: { ($0 as AnyObject) === coordinator.overlay }) {
            map.removeOverlay(coordinator.overlay)
        }
        coordinator.appliedPrefix = ""
    }

    private func applyRain(_ prefix: String, map: MKMapView, coordinator: Coordinator) {
        guard !prefix.isEmpty else { return }
        let prefixChanged = coordinator.appliedPrefix != prefix
        let alreadyAdded = map.overlays.contains { ($0 as AnyObject) === coordinator.overlay }
        if prefixChanged {
            coordinator.overlay.framePrefix = prefix
            coordinator.appliedPrefix = prefix
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
        let noaa = NOAARadarLayer()
        var renderer: MKTileOverlayRenderer?
        var onSettled: ((String) -> Void)?
        var lastCoordinate: CLLocationCoordinate2D?
        var lastTitle: String?
        var appliedPrefix = ""

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            noaa.regionDidChange()
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? RainViewerRadarOverlay {
                if let renderer, renderer.overlay === tile {
                    return renderer
                }
                let created = MKTileOverlayRenderer(tileOverlay: tile)
                created.alpha = 0.7
                renderer = created
                return created
            }
            if overlay is NOAAImageOverlay {
                let created = NOAAImageRenderer(overlay: overlay)
                created.alpha = 1
                return created
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
