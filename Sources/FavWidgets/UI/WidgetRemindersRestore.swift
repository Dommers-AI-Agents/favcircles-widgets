import Foundation
import FavWidgetsCore

/// A reinstalled app (or a second phone) has no local notifications: the
/// reminders a person set in Water, Meds and Motivation live in their saved
/// documents, and each scheduler only ran when its widget was opened. The
/// app calls this when it comes to the foreground, signed in, so the
/// reminders come back without opening each widget (2026-11-01).
public enum WidgetRemindersRestore {

    public static func refreshAll(store: WidgetDataStore, quietHours: WidgetQuietHours? = nil) async {
        await MotivationReminderScheduler.refresh(store: store, quietHours: quietHours)
        if let water = await load(WaterLog.self, id: WaterLog.documentId, store: store), water.reminders.enabled {
            await WaterReminderScheduler.syncIfMissing(water, quietHours: quietHours)
        }
        if let meds = await load(MedSettings.self, id: MedQuickLog.widgetId, store: store), !meds.meds.isEmpty {
            await MedReminderScheduler.syncIfChanged(meds)
        }
    }

    private static func load<M: WidgetModel>(_ type: M.Type, id: String, store: WidgetDataStore) async -> M? {
        guard let document = try? await store.load(id: id) else { return nil }
        return try? WidgetDocumentCodec.decode(type, from: document.payload)
    }
}
