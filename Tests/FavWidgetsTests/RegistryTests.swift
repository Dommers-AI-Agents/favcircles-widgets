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
