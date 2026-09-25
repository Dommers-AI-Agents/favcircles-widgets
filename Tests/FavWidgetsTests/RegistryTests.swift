import Testing
import Foundation
@testable import FavWidgets
@testable import FavWidgetsCore

@MainActor
struct RegistryTests {
    @Test func idsAreUniqueAndValid() {
        let ids = FavWidgetRegistry.descriptors.map(\.id)
        #expect(Set(ids).count == ids.count)
        for id in ids {
            #expect(FavWidgetDescriptor.isValidId(id), "bad id \(id)")
            #expect(!id.contains("_"), "underscore is reserved for month shards: \(id)")
        }
        #expect(!ids.contains(WidgetPreferences.documentId))
    }

    /// The share sheet shows the pitch alone above a link that already names
    /// the widget, so every widget needs one, written as a full sentence
    /// to someone who doesn't have the app.
    @Test func everyWidgetHasAShareSentence() {
        for d in FavWidgetRegistry.descriptors {
            let pitch = d.shareText
            #expect(d.shareBlurb != nil, "\(d.id) shares its card subtitle")
            #expect(pitch.first?.isUppercase == true, "\(d.id): \(pitch)")
            #expect(pitch.last.map { ".!?".contains($0) } == true, "\(d.id): \(pitch)")
            #expect(!pitch.hasPrefix(d.title + " on FavCircles"), "\(d.id) repeats the link's own title: \(pitch)")
        }
    }

    @Test func everyWidgetBuildsItsViews() {
        let host = MockWidgetHost()
        let model = WidgetsTabModel(host: host)
        for widget in FavWidgetRegistry.all {
            let context = model.context(for: widget.descriptor)
            _ = widget.makeCardView(context: context)
            _ = widget.makeFullView(context: context)
        }
        #expect(model.visible.count == FavWidgetRegistry.all.filter { $0.descriptor.defaultEnabled }.count)
    }

    @Test func tabModelPreloadsHotSetInOneBatch() async {
        let store = InMemoryWidgetDataStore()
        let host = MockWidgetHost(dataStore: store)
        let model = WidgetsTabModel(host: host)
        await model.loadIfNeeded()
        #expect(store.loadCount == 1)
        #expect(model.hasLoaded && model.loadError == nil)
        model.setEnabled(false, id: "water")
        #expect(!model.visible.contains { $0.id == "water" })
        model.move(from: IndexSet(integer: 0), to: 2)
        #expect(model.ordered.first?.id != "water")
    }
}
