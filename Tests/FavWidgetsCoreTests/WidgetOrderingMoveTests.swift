import Testing
import Foundation
@testable import FavWidgetsCore

/// Dragging a card on the tab reorders only the visible widgets; disabled
/// ones keep their slots in the full order.
struct WidgetOrderingMoveTests {
    // full order: a b X c d   (X disabled → not on the tab)
    private let all = ["a", "b", "X", "c", "d"]
    private let visible = ["a", "b", "c", "d"]

    @Test func dragLastVisibleToFrontKeepsDisabledSlot() {
        let next = WidgetOrdering.movingVisible(all: all, visibleIds: visible, fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(next == ["d", "a", "X", "b", "c"])
    }

    @Test func dragFirstToEndUsesListOnMoveSemantics() {
        let next = WidgetOrdering.movingVisible(all: all, visibleIds: visible, fromOffsets: IndexSet(integer: 0), toOffset: 4)
        #expect(next == ["b", "c", "X", "d", "a"])
    }

    @Test func noOpMoveAndMiddleMove() {
        #expect(WidgetOrdering.movingVisible(all: all, visibleIds: visible, fromOffsets: IndexSet(integer: 1), toOffset: 1) == all)
        #expect(WidgetOrdering.movingVisible(all: all, visibleIds: visible, fromOffsets: IndexSet(integer: 1), toOffset: 3) == ["a", "c", "X", "b", "d"])
    }

    @Test func fullOrderAndVisibleAgreeAfterAMove() {
        let descriptors = ["a", "b", "X", "c", "d"].map { FavWidgetDescriptor(id: $0, title: $0, subtitle: "", symbolName: "star", accentHex: "#000000", category: FavWidgetCategory.allCases.first!) }
        var prefs = WidgetPreferences(order: all, disabled: ["X"])
        let vis = WidgetOrdering.visible(prefs: prefs, descriptors: descriptors).map(\.id)
        #expect(vis == visible)
        prefs.order = WidgetOrdering.movingVisible(all: prefs.order, visibleIds: vis, fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(WidgetOrdering.visible(prefs: prefs, descriptors: descriptors).map(\.id) == ["d", "a", "b", "c"])
        #expect(WidgetOrdering.all(prefs: prefs, descriptors: descriptors).map(\.id) == ["d", "a", "X", "b", "c"])
    }
}
