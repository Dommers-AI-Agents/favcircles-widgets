import SwiftUI
import PhotosUI
import FavWidgetsCore

extension FridgeMailFullView {
    func run(_ key: String, _ op: @escaping () async throws -> FridgeMailPlan?) {
        guard busy == nil else { return }
        busy = key
        Task {
            defer { busy = nil }
            do {
                if let plan = try await op() { store.apply(plan) }
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Fridge Mail", message: error.localizedDescription))
            }
        }
    }

    func setWeekday(_ day: Int) {
        context.track("fridgemail_weekday", ["weekday": "\(day)"])
        run("weekday") { try await FridgeMailAPI.updatePlan(context: context, weekday: day, timezone: TimeZone.current.identifier) }
    }

    func saveFamilyName() {
        let name = familyNameDraft.trimmingCharacters(in: .whitespaces)
        run("family") { try await FridgeMailAPI.updatePlan(context: context, familyName: name) }
    }

    func moveToTop(_ item: FridgeMailQueueItem, pending: [FridgeMailQueueItem]) {
        let ids = [item.id] + pending.map(\.id).filter { $0 != item.id }
        run("reorder") { try await FridgeMailAPI.reorderQueue(context: context, ids: ids) }
    }

    func remove(_ item: FridgeMailQueueItem) {
        run("remove") { try await FridgeMailAPI.removeQueued(context: context, id: item.id) }
    }

    func removeRecipient(_ recipient: FridgeMailRecipient) {
        run("recipient") { try await FridgeMailAPI.removeRecipient(context: context, id: recipient.id) }
    }

    func buy(_ pack: FridgeMailPack) {
        guard let config = store.config else { return }
        context.track("fridgemail_pack_tap", ["pack": pack.id])
        run(pack.id) {
            let plan = try await FridgeMailAPI.purchasePack(context: context, pack: pack, config: config)
            if plan != nil { context.host.haptic(.success) }
            return plan
        }
    }

    func subscribe(_ plan: FridgeMailPlan) {
        guard let config = store.config else { return }
        context.track("fridgemail_subscribe_tap")
        run("subscribe") {
            let updated = try await FridgeMailAPI.subscribe(context: context, plan: plan, config: config)
            if updated != nil { context.host.haptic(.success) }
            return updated
        }
    }

    func loadPhoto(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = PostcardPlatformImage(data: data) else {
                context.host.presentAlert(WidgetAlert(title: "Couldn't load photo", message: "That photo couldn't be read. Try another one."))
                return
            }
            pickedImage = image
            context.host.haptic(.light)
        } catch {
            context.host.presentAlert(WidgetAlert(title: "Couldn't load photo", message: error.localizedDescription))
        }
    }
}
