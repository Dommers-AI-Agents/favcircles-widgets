import SwiftUI
import FavWidgetsCore
#if os(iOS)
import MapKit

/// "Precipitation": live NEXRAD radar over a map around the place, like the
/// Weather app's card. Tap for a full-screen map you can pan and zoom.
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
            NavigationStack {
                WeatherRadarMap(latitude: latitude, longitude: longitude, interactive: true)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Rain radar")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { expanded = false } }
                    }
            }
        }
    }
}

/// MKMapView with the radar tiles laid over it (SwiftUI's Map can't take a
/// tile overlay before iOS 17).
struct WeatherRadarMap: UIViewRepresentable {
    let latitude: Double
    let longitude: Double
    let interactive: Bool

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
        let radar = MKTileOverlay(urlTemplate: WeatherRadar.tileTemplate)
        radar.canReplaceMapContent = false
        radar.maximumZ = 12   // the mesonet cache stops adding detail past this
        map.addOverlay(radar, level: .aboveRoads)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tiles = overlay as? MKTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKTileOverlayRenderer(tileOverlay: tiles)
            renderer.alpha = 0.75
            return renderer
        }
    }
}
#endif
