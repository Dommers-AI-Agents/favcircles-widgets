import Testing
import Foundation
@testable import FavWidgetsCore

struct WiFiPlanTests {
    private let home = WidgetCoordinate(latitude: 35.2271, longitude: -80.8431)
    private let cafe = WidgetCoordinate(latitude: 35.2300, longitude: -80.8400)

    @Test func hereIsTheNearestSpotWithinRange() {
        let spots = [WiFiSpot(id: "h", placeName: "Home", coordinate: home, network: "Sgroi", password: "x"),
                     WiFiSpot(id: "c", placeName: "Café", coordinate: cafe, network: "Cafe", password: "")]
        #expect(WiFiPlan.here(spots, at: WidgetCoordinate(latitude: 35.2272, longitude: -80.8432))?.id == "h")
        #expect(WiFiPlan.here(spots, at: WidgetCoordinate(latitude: 35.25, longitude: -80.9)) == nil)
        #expect(WiFiPlan.here(spots, at: nil) == nil)
        #expect(WiFiPlan.sorted(spots, near: cafe).map(\.id) == ["c", "h"])
    }

    @Test func qrPayloadEscapesAndHandlesOpenNetworks() {
        #expect(WiFiPlan.qrPayload(network: "Sgroi", password: "p@ss") == "WIFI:T:WPA;S:Sgroi;P:p@ss;;")
        #expect(WiFiPlan.qrPayload(network: "a;b", password: #"c:d,"e\"#) == #"WIFI:T:WPA;S:a\;b;P:c\:d\,\"e\\;;"#)
        #expect(WiFiPlan.qrPayload(network: "Open", password: "") == "WIFI:T:nopass;S:Open;;")
        #expect(WiFiPlan.masked("abc") == "••••••")
        #expect(WiFiPlan.masked("") == "Open network")
    }

    @Test func nearestSavedPlaceStandsInForHere() {
        let places = [WidgetPlaceCandidate(id: "a", name: "A", coordinate: home, category: "home", source: .mine),
                      WidgetPlaceCandidate(id: "b", name: "B", coordinate: cafe, category: "cafe", source: .mine)]
        #expect(WiFiPlan.nearestPlace(places, to: WidgetCoordinate(latitude: 35.2301, longitude: -80.8401))?.id == "b")
        #expect(WiFiPlan.nearestPlace(places, to: WidgetCoordinate(latitude: 36, longitude: -81)) == nil)
    }

    @Test func mergeKeepsTheLaterEdit() {
        var local = WiFiSpot(id: "h", placeName: "Home", network: "Sgroi", password: "old")
        var remote = local
        remote.password = "new"; remote.updatedAt = local.updatedAt.addingTimeInterval(60)
        local.note = "stale"
        let merged = WiFiSpotList.merge(local: WiFiSpotList(spots: [local]), remote: WiFiSpotList(spots: [remote]))
        #expect(merged.spots.count == 1 && merged.spots[0].password == "new")
    }
}
