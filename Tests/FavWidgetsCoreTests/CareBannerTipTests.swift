import Testing
@testable import FavWidgetsCore

/// The "keep questions on screen" shortcut for the person being checked on.
struct CareBannerTipTests {
    @Test func onlyWhileBannersAreTemporaryForSomeoneBeingAsked() {
        #expect(CareBannerTip.shouldShow(style: .temporary, isAskedSomething: true, dismissed: false))
        #expect(!CareBannerTip.shouldShow(style: .persistent, isAskedSomething: true, dismissed: false))
        #expect(!CareBannerTip.shouldShow(style: .temporary, isAskedSomething: false, dismissed: false))
        #expect(!CareBannerTip.shouldShow(style: .temporary, isAskedSomething: true, dismissed: true))
        #expect(!CareBannerTip.shouldShow(style: .unknown, isAskedSomething: true, dismissed: false))
    }
}
