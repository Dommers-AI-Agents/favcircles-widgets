import SwiftUI
import FavWidgetsCore
#if os(iOS)
import MapKit

/// "Precipitation": live NEXRAD radar over a map around the place, like the
/// Weather app's card. Tap for a full-screen map that plays the last 50
/// minutes, and that you can pan and zoom.
struct WeatherRadarCard: View {
    let latitude: Double
    let longitude: Double
    let theme: WidgetTheme
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("PRECIPITATION", systemImage: "umbrella.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.secondaryLabel)
            WeatherRadarMap(latitude: latitude, longitude: longitude, interactive: false)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(8)
                }
                .contentShape(Rectangle())
                .onTapGesture { expanded = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Rain radar map. Opens full screen")
            Text(WeatherRadar.credit)
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryLabel)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.secondaryBackground))
        .fullScreenCover(isPresented: $expanded) {
            WeatherRadarPlayer(latitude: latitude, longitude: longitude) { expanded = false }
        }
    }
}

/// Full-screen radar that plays the last 50 minutes, like the Weather app:
/// play/pause, a scrubber, and when the picture is from. It starts playing
/// and holds on "Now" for a beat before looping.
struct WeatherRadarPlayer: View {
    let latitude: Double
    let longitude: Double
    let onDone: () -> Void
    @State private var index = WeatherRadar.frames.count - 1
    @State private var playing = true
    @State private var held = 0
    private let tick = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                WeatherRadarMap(latitude: latitude, longitude: longitude, interactive: true,
                                frames: WeatherRadar.frames, shownIndex: index)
                    .ignoresSafeArea(edges: .bottom)
                controls
            }
            .navigationTitle("Rain radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
            }
        }
        .onReceive(tick) { _ in
            guard playing else { return }
            let next = WeatherRadar.nextIndex(after: index, holdTicks: 2, held: held)
            index = next.index
            held = next.held
        }
    }

    private var controls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                Button {
                    playing.toggle()
                    held = 0
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(playing ? "Pause" : "Play")
                Slider(value: Binding(get: { Double(index) },
                                      set: { index = Int($0.rounded()); playing = false; held = 0 }),
                       in: 0...Double(WeatherRadar.frames.count - 1), step: 1)
                Text(WeatherRadar.frames[index].label)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .frame(width: 92, alignment: .trailing)
            }
            Text(WeatherRadar.credit)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 24)
    }
}

/// MKMapView with the radar tiles laid over it (SwiftUI's Map can't take a
/// tile overlay before iOS 17). For playback every frame is its own overlay,
/// so all of them load once; only `shownIndex` is drawn, and stepping is a
/// change of opacity, not a reload.
struct WeatherRadarMap: UIViewRepresentable {
    let latitude: Double
    let longitude: Double
    let interactive: Bool
    var frames: [WeatherRadar.Frame] = [WeatherRadar.Frame(minutesAgo: 0)]
    var shownIndex: Int = 0

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.isScrollEnabled = interactive
        map.isZoomEnabled = interactive
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        map.setRegion(MKCoordinateRegion(center: center,
                                         span: MKCoordinateSpan(latitudeDelta: WeatherRadar.spanDegrees,
                                                                longitudeDelta: WeatherRadar.spanDegrees)),
                      animated: false)
        let pin = MKPointAnnotation()
        pin.coordinate = center
        map.addAnnotation(pin)
        context.coordinator.shownIndex = shownIndex
        for (i, frame) in frames.enumerated() {
            let tiles = MKTileOverlay(urlTemplate: frame.tileTemplate)
            tiles.canReplaceMapContent = false
            tiles.maximumZ = 12   // the mesonet cache stops adding detail past this
            context.coordinator.frameOf[ObjectIdentifier(tiles)] = i
            map.addOverlay(tiles, level: .aboveRoads)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.show(shownIndex)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let opacity: CGFloat = 0.75
        var frameOf: [ObjectIdentifier: Int] = [:]
        var renderers: [Int: MKTileOverlayRenderer] = [:]
        var shownIndex = 0

        func show(_ index: Int) {
            guard index != shownIndex else { return }
            // An alpha change alone doesn't always repaint a tile layer
            if let leaving = renderers[shownIndex] { leaving.alpha = 0; leaving.setNeedsDisplay() }
            if let arriving = renderers[index] { arriving.alpha = Self.opacity; arriving.setNeedsDisplay() }
            shownIndex = index
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tiles = overlay as? MKTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKTileOverlayRenderer(tileOverlay: tiles)
            let index = frameOf[ObjectIdentifier(tiles)] ?? 0
            renderer.alpha = index == shownIndex ? Self.opacity : 0
            renderers[index] = renderer
            return renderer
        }
    }
}
#endif
