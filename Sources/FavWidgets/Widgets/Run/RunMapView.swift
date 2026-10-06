import SwiftUI
#if os(iOS)
import MapKit

/// The route as a line on a map (MKMapView: SwiftUI's Map can't draw a
/// polyline before iOS 17). Live runs follow you; saved runs fit the route.
struct RunMapView: UIViewRepresentable {
    let coordinates: [(Double, Double)]
    let followsUser: Bool
    let tint: Color

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = followsUser
        map.isRotateEnabled = false
        map.pointOfInterestFilter = .excludingAll
        if followsUser { map.setUserTrackingMode(.follow, animated: false) }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.tint = UIColor(tint)
        guard context.coordinator.drawnCount != coordinates.count else { return }
        context.coordinator.drawnCount = coordinates.count
        map.removeOverlays(map.overlays)
        let points = coordinates.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }
        guard points.count > 1 else { return }
        let line = MKPolyline(coordinates: points, count: points.count)
        map.addOverlay(line)
        if !followsUser {
            map.setVisibleMapRect(line.boundingMapRect, edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24), animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var tint: UIColor = .systemOrange
        var drawnCount = -1
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let r = MKPolylineRenderer(overlay: overlay)
            r.strokeColor = tint
            r.lineWidth = 5
            r.lineCap = .round
            r.lineJoin = .round
            return r
        }
    }
}
#else
struct RunMapView: View {
    let coordinates: [(Double, Double)]
    let followsUser: Bool
    let tint: Color
    var body: some View { Color.gray.opacity(0.2) }
}
#endif
