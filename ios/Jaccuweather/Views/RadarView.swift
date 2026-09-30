import SwiftUI
import MapKit
import CoreLocation

struct RadarView: View {
    @Environment(WeatherViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    var isActive = true
    @State private var noaaFrames: [NOAARadarCatalog.Frame] = []
    @State private var noaaIndex = 0
    @State private var playing = false
    @State private var tilesSettled = false
    @State private var noaaError: String?
    @State private var playTask: Task<Void, Never>?

    private var theme: JWPalette { JWPalette.forScheme(colorScheme) }

    private var mosaic: NOAAMosaic? {
        NOAAMosaic.containing(latitude: model.coordinate.latitude, longitude: model.coordinate.longitude)
    }

    private var settleToken: String {
        guard let mosaic, noaaFrames.indices.contains(noaaIndex) else { return "" }
        return "noaa|\(mosaic.id)|\(noaaFrames[noaaIndex].stamp)"
    }

    private var mapLayer: RadarMapView.Layer {
        guard let mosaic, noaaFrames.indices.contains(noaaIndex) else { return .empty }
        let frame = noaaFrames[noaaIndex]
        return .noaa(
            mosaicID: mosaic.id,
            stamp: frame.stamp,
            token: "noaa|\(mosaic.id)|\(frame.stamp)"
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            RadarMapView(
                coordinate: model.coordinate,
                title: model.locationName,
                layer: mapLayer,
                onTilesSettled: { token in
                    if token == settleToken { tilesSettled = true }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: JWMetrics.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: JWMetrics.radius, style: .continuous)
                    .stroke(theme.cardStroke, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay {
                if mosaic == nil { unavailableBanner }
            }
            .overlay(alignment: .topLeading) {
                Text(model.locationName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(theme.cardStroke, lineWidth: 1))
                    .padding(12)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 12) {
                Text("Weather Radar")
                    .font(JWFont.section)
                    .tracking(-0.32)

                if mosaic == nil {
                    unavailableCopy
                } else {
                    playbackControls
                    Text(timeLabel)
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(theme.text)
                    intensityLegend
                    Link(destination: APIEndpoints.noaaRadarCredit) {
                        Text("NOAA / NWS MRMS")
                            .font(.caption.weight(.semibold))
                            .underline()
                    }
                    .accessibilityLabel("NOAA / NWS MRMS")
                    .accessibilityIdentifier("noaa-radar-credit")
                }
            }
            .padding(JWMetrics.panelPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jwGlass(.panel)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .tint(theme.accent)
        .background { HorizonBackground() }
        .navigationTitle("Radar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await refreshLoop() }
        .onChange(of: isActive) { _, active in
            if active {
                Task { await refreshNOAA(resetToLatest: false) }
            } else {
                setPlaying(false)
            }
        }
        .onChange(of: mosaic?.id) { old, new in
            guard old != new else { return }
            setPlaying(false)
            tilesSettled = false
            if new == nil {
                noaaFrames = []
                noaaError = nil
                return
            }
            Task { await refreshNOAA(resetToLatest: true) }
        }
        .onDisappear { setPlaying(false) }
    }

    private var unavailableBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Radar unavailable")
                .font(.headline)
            Text("This place is outside NOAA radar coverage.")
                .font(.subheadline)
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.cardStroke, lineWidth: 1)
        )
        .padding(28)
        .accessibilityIdentifier("radar-unavailable")
    }

    private var unavailableCopy: some View {
        Text("NOAA radar covers the mainland United States, Alaska, Hawaii, the Caribbean, and Guam. This place is outside that coverage, so there is no radar image to play.")
            .font(.subheadline)
            .foregroundStyle(theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var playbackControls: some View {
        HStack(spacing: 12) {
            Button {
                setPlaying(!playing)
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.text)
                    .frame(width: 36, height: 36)
                    .background(theme.glassStrong, in: Circle())
                    .overlay(Circle().stroke(theme.cardStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(noaaFrames.count < 2)
            .opacity(noaaFrames.count < 2 ? 0.45 : 1)
            .accessibilityLabel(playing ? "Pause radar" : "Play radar")

            if noaaFrames.count > 1 {
                Slider(
                    value: Binding(
                        get: { Double(noaaIndex) },
                        set: { newValue in
                            setPlaying(false)
                            selectFrame(Int(newValue.rounded()))
                        }
                    ),
                    in: 0...Double(noaaFrames.count - 1),
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
    }

    /// Qualitative echo key for the NOAA reflectivity ramp.
    private var intensityLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("INTENSITY")
                .font(JWFont.eyebrow)
                .tracking(1.1)
                .foregroundStyle(theme.muted)
            HStack(spacing: 4) {
                ForEach(Self.legendStops, id: \.label) { stop in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(stop.color)
                        .frame(height: 8)
                        .accessibilityHidden(true)
                }
            }
            HStack {
                Text("Light")
                Spacer()
                Text("Heavy")
            }
            .font(.caption2)
            .foregroundStyle(theme.faint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Precipitation intensity from light to heavy")
    }

    private static let legendStops: [(label: String, color: Color)] = [
        ("Light", Color(red: 110 / 255, green: 210 / 255, blue: 235 / 255)),
        ("Moderate", Color(red: 80 / 255, green: 200 / 255, blue: 90 / 255)),
        ("Steady", Color(red: 250 / 255, green: 214 / 255, blue: 60 / 255)),
        ("Heavy", Color(red: 245 / 255, green: 130 / 255, blue: 40 / 255)),
        ("Intense", Color(red: 230 / 255, green: 50 / 255, blue: 55 / 255))
    ]

    private var statusLine: String {
        if noaaFrames.isEmpty { return noaaError ?? "Loading radar…" }
        return "One radar frame"
    }

    private var timeLabel: String {
        let formatter = Self.timeFormatter(utcOffset: model.weather?.utcOffset ?? 0)
        guard noaaFrames.indices.contains(noaaIndex) else {
            return noaaError ?? "Loading radar…"
        }
        return formatter.string(from: noaaFrames[noaaIndex].time)
    }

    private static func timeFormatter(utcOffset: Int) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(secondsFromGMT: utcOffset)
        formatter.setLocalizedDateFormatFromTemplate("EEE h:mm a")
        return formatter
    }

    private func refreshLoop() async {
        await refreshNOAA(resetToLatest: false)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            if Task.isCancelled { return }
            if isActive {
                await refreshNOAA(resetToLatest: false)
            }
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
            if settleToken != oldToken { tilesSettled = false }
            noaaError = loaded.isEmpty ? "NOAA radar unavailable" : nil
            if loaded.count < 2 { setPlaying(false) }
        } catch {
            if noaaFrames.isEmpty { noaaError = "NOAA radar unavailable" }
        }
    }

    private func selectFrame(_ index: Int) {
        guard noaaFrames.indices.contains(index), index != noaaIndex else { return }
        tilesSettled = false
        noaaIndex = index
    }

    private func setPlaying(_ on: Bool) {
        playTask?.cancel()
        playTask = nil
        guard on, noaaFrames.count > 1 else {
            playing = false
            return
        }
        playing = true
        playTask = Task { await runPlayback() }
    }

    private func runPlayback() async {
        while !Task.isCancelled && playing && noaaFrames.count > 1 {
            let shownAt = Date()
            while !Task.isCancelled && playing && !tilesSettled && Date().timeIntervalSince(shownAt) < 4 {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            let remain = 0.85 - Date().timeIntervalSince(shownAt)
            if remain > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remain * 1_000_000_000))
            }
            guard !Task.isCancelled, playing, noaaFrames.count > 1 else { return }
            selectFrame((noaaIndex + 1) % noaaFrames.count)
            await Task.yield()
        }
    }
}

struct RadarMapView: UIViewRepresentable {
    enum Layer: Equatable {
        case empty
        case noaa(mosaicID: String, stamp: String, token: String)
    }

    let coordinate: CLLocationCoordinate2D
    let title: String
    let layer: Layer
    let onTilesSettled: (String) -> Void

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.noaa.onSettled = { [weak coordinator] token in
            coordinator?.onSettled?(token)
        }
        return coordinator
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        let config = MKStandardMapConfiguration(emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config
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
        case .noaa(let mosaicID, let stamp, let token):
            if let mosaic = NOAAMosaic.mosaic(id: mosaicID) {
                coordinator.noaa.activate(mosaic: mosaic, stamp: stamp, token: token, map: map)
            } else {
                coordinator.noaa.deactivate(on: map)
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let noaa = NOAARadarLayer()
        var onSettled: ((String) -> Void)?
        var lastCoordinate: CLLocationCoordinate2D?
        var lastTitle: String?

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            noaa.regionDidChange()
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is NOAAImageOverlay {
                let created = NOAAImageRenderer(overlay: overlay)
                created.alpha = 1
                return created
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
