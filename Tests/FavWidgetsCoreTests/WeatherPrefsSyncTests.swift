import Testing
import Foundation
@testable import FavWidgetsCore

/// Weather's places and units live on the account (2026-11-01)
struct WeatherPrefsSyncTests {
    private let charlotte = WeatherPlace(name: "Charlotte", latitude: 35.23, longitude: -80.84)
    private var withCity: WeatherPrefs { var p = WeatherPrefs(); p.addPlace(charlotte); return p }

    @Test func aReinstallTakesTheAccountsChoices() {
        #expect(WeatherPrefsSync.decide(phone: .empty, account: withCity, accountSaved: true) == .adoptAccount)
    }

    @Test func aPhoneSetUpBeforeTheDocumentSendsItsChoicesUpOnce() {
        #expect(WeatherPrefsSync.decide(phone: withCity, account: .empty, accountSaved: false) == .uploadPhone)
        #expect(WeatherPrefsSync.decide(phone: .empty, account: .empty, accountSaved: false) == .nothing)
    }

    @Test func inStepNothingHappens() {
        #expect(WeatherPrefsSync.decide(phone: withCity, account: withCity, accountSaved: true) == .nothing)
    }

    @Test func postcardSettingsWithoutTheNewFieldStillDecode() throws {
        let old = try WidgetDocumentCodec.decode(PostcardSettings.self, from: Data(#"{"lastTemplateId":"classic"}"#.utf8))
        #expect(old.showInActivity == nil)
    }
}
