import Foundation
import Testing
import FavWidgetsCore
@testable import FavWidgets

/// The shell calls `shareCard` on `any FavWidget`; each widget's own card
/// must win over the protocol's nil default.
@MainActor
struct ShareCardDispatchTests {
    private func context(_ id: String) -> (any FavWidget, WidgetContext) {
        let widget = FavWidgetRegistry.widget(id: id)!
        let model = WidgetsTabModel(host: MockWidgetHost(), theme: .default)
        return (widget, model.context(for: widget.descriptor))
    }

    @Test func waterAndCoachUseTheirOwnCards() async {
        let (water, wc) = context("water")
        #expect(await water.shareCard(context: wc)?.headline.hasSuffix("cups today") == true)
        let (coach, cc) = context("motivation")
        #expect(await coach.shareCard(context: cc)?.headline == "Coach Mane says")
        let (sleep, sc) = context("sleepsounds")
        #expect(await sleep.shareCard(context: sc)?.headline.hasPrefix("Falling asleep to") == true)
    }

    @Test func emptyWidgetsFallBackToGeneric() async {
        let (habits, hc) = context("habits")
        #expect(await habits.shareCard(context: hc) == nil) // no habits yet → generic card
        let (contacts, nc) = context("newcontacts")
        #expect(await contacts.shareCard(context: nc) == nil) // private → always generic
    }
}
