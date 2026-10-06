import SwiftUI
import FavWidgetsCore

/// Events (first use: a Party Bus, Wes 2026-10-04): photos only the people
/// who joined can see, places everyone went, a circle and an Inner Circle
/// list named after the event. Server-backed (`/api/widgets/events`).
public struct EventsWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "events",
        title: "Events",
        subtitle: "Photos and plans only your group sees",
        symbolName: "party.popper.fill",
        accentHex: "#7B2FF7",
        category: .social,
        storage: .single,
        shareBlurb: "Start an event (a party bus, a trip, a night out): everyone joins with one link, shares photos only the group can see, and saves the places you went."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(EventsCardView(context: context, store: EventsStore.shared(in: context)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(EventsFullView(context: context, store: EventsStore.shared(in: context)))
    }

    public func refresh(context: WidgetContext) async {
        await EventsStore.shared(in: context).refresh(context, force: true)
    }
}

/// Card: the newest event and its counts, or the pitch.
struct EventsCardView: View {
    let context: WidgetContext
    @ObservedObject var store: EventsStore

    var body: some View {
        let theme = context.theme
        WidgetCard(context: context, action: WidgetQuickAction("New", symbolName: "plus") { context.openFullView() }) {
            if let event = store.events.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(event.emoji) \(event.name)")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(theme.label).lineLimit(1)
                    Text("\(EventCopy.memberCount(event.members.count)) · \(event.photoCount) photo\(event.photoCount == 1 ? "" : "s")")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
            } else {
                WidgetUI.summary("Start an event 🎉 and share photos with just your group", theme: theme)
            }
        }
        .task { await store.refresh(context) }
    }
}
