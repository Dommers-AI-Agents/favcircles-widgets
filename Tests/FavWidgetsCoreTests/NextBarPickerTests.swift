import Testing
import Foundation
@testable import FavWidgetsCore

struct NextBarPickerTests {
    private func bar(_ id: String, lat: Double, lon: Double, source: WidgetPlaceSource = .mine, name: String? = nil) -> WidgetPlaceCandidate {
        WidgetPlaceCandidate(id: id, name: name ?? id, coordinate: WidgetCoordinate(latitude: lat, longitude: lon), category: "bar", source: source)
    }

    private let home = WidgetCoordinate(latitude: 40.7484, longitude: -73.9857)   // Empire State

    @Test func haversineIsRoughlyRight() {
        let timesSquare = WidgetCoordinate(latitude: 40.7580, longitude: -73.9855)
        let d = home.distance(to: timesSquare)
        #expect(d > 1_000 && d < 1_150)   // ~1.07 km
    }

    @Test func poolFiltersByDistanceSourceAndDedupes() {
        let near = bar("near", lat: 40.7500, lon: -73.9860)
        let nearCopy = bar("near-copy", lat: 40.7500, lon: -73.9860, source: .connection, name: "Near")
        let far = bar("far", lat: 40.8500, lon: -73.9860)
        let following = bar("fol", lat: 40.7490, lon: -73.9850, source: .following)
        let pool = NextBarPicker.pool([far, nearCopy, near, following], origin: home, maxDistanceMeters: 2_000, sources: [.mine, .connection])
        #expect(pool.map(\.candidate.id) == ["near-copy"])   // dedup keeps the first copy; far out of range; following excluded
        let all = NextBarPicker.pool([far, near, following], origin: nil, maxDistanceMeters: 1, sources: Set(WidgetPlaceSource.allCases))
        #expect(all.count == 3)   // no origin → no distance cut
    }

    @Test func pickIsWeightedTowardNearAndSkipsRecent() {
        let near = bar("near", lat: 40.7490, lon: -73.9857)
        let far = bar("far", lat: 40.7800, lon: -73.9857)
        let pool = NextBarPicker.pool([far, near], origin: home, maxDistanceMeters: 10_000, sources: [.mine])
        #expect(pool.first?.candidate.id == "near")
        // Low random values land on the heaviest (nearest) entry.
        #expect(NextBarPicker.pick(from: pool, excluding: [], random: { 0.01 })?.candidate.id == "near")
        // Skipping the near one leaves far as the only fresh choice.
        #expect(NextBarPicker.pick(from: pool, excluding: ["near"], random: { 0.01 })?.candidate.id == "far")
        // Everything recent → fall back to the whole pool rather than nothing.
        #expect(NextBarPicker.pick(from: pool, excluding: ["near", "far"], random: { 0.01 }) != nil)
        #expect(NextBarPicker.pick(from: [], excluding: []) == nil)
        #expect(NextBarPicker.weight(distanceMeters: 0) > NextBarPicker.weight(distanceMeters: 1_000) * 10)
    }

    @Test func settingsRingAndMerge() {
        var s = NextBarSettings()
        for i in 0..<12 { s.notePick(NextBarPick(day: DayKey(rawValue: "2026-09-13"), placeId: "p\(i)", name: "", source: .mine, savedByName: nil, distanceMeters: 0)) }
        #expect(s.recentPickIds.count == NextBarSettings.recentLimit && s.recentPickIds.last == "p11")
        var other = NextBarSettings()
        other.visits.append(NextBarVisit(placeId: "x", name: "X", source: .mine, savedByName: nil, distanceMeters: 1))
        #expect(NextBarSettings.merge(local: s, remote: other).visits.count == 1)
    }
}

struct NextBarAttributionTests {
    @Test func phrasesSavers() {
        #expect(NextBarAttribution.text(savers: ["You"], fallbackSource: .mine) == "on your list")
        #expect(NextBarAttribution.text(savers: ["You", "Ana"], fallbackSource: .mine) == "you + Ana")
        #expect(NextBarAttribution.text(savers: ["Ana", "Joe"], fallbackSource: .connection) == "saved by Ana, Joe")
        #expect(NextBarAttribution.text(savers: ["A", "B", "C", "D", "E"], fallbackSource: .connection) == "saved by A, B, C +2")
        #expect(NextBarAttribution.text(savers: [], fallbackSource: .following, fallbackName: "Kim") == "via Kim")
        #expect(NextBarAttribution.text(savers: [], fallbackSource: .connection) == "saved by a connection")
    }
}
