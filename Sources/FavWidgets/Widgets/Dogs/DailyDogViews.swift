import SwiftUI
import FavWidgetsCore

/// Daily Dog: today's card, when it arrives, and the ones before.
struct DailyDogTab: View {
    let context: WidgetContext
    @ObservedObject var store: DogsStore
    let onOpen: (DailyDog) -> Void
    @State private var saving = false

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let today = store.me.today {
                    Button { onOpen(today) } label: { DailyDogCard(context: context, item: today, big: true) }
                        .buttonStyle(.plain)
                } else {
                    Text("Today's Daily Dog is on its way 🐾").font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
                }
                settings(theme)
                if !past.isEmpty {
                    WidgetUI.header("Earlier", theme: theme)
                    ForEach(past) { item in
                        Button { onOpen(item) } label: { DailyDogCard(context: context, item: item, big: false) }
                            .buttonStyle(.plain)
                            .onAppear {
                                if item.id == past.last?.id, store.dailyHasMore { Task { await store.loadDaily(context: context, more: true) } }
                            }
                    }
                }
            }
            .padding(16)
            .disabled(saving)
        }
        .refreshable {
            await store.refresh(context, force: true)
            await store.loadDaily(context: context)
        }
        .task { if store.daily.isEmpty { await store.loadDaily(context: context) } }
    }

    private var past: [DailyDog] { store.daily.filter { $0.id != store.me.today?.id } }

    private func settings(_ theme: WidgetTheme) -> some View {
        let prefs = store.me.prefs
        return VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { prefs.enabled }, set: { save(enabled: $0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send me a Daily Dog").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                    Text("A funny dog thing, or the Dog Park's most-petted pup. As a notification.")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
            }
            .tint(context.accent)
            if prefs.enabled {
                Divider()
                ForEach(Array(prefs.times.enumerated()), id: \.offset) { index, slot in
                    HStack {
                        DatePicker("", selection: Binding(
                            get: { QuoteSettings.date(from: slot) },
                            set: { newValue in
                                let time = QuoteSettings.time(from: newValue, calendar: context.calendar)
                                guard time != slot else { return }
                                var next = prefs.times
                                next[index] = time
                                save(times: next)
                            }
                        ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(context.accent)
                        Spacer()
                        if prefs.times.count > 1 {
                            Button {
                                var next = prefs.times
                                next.remove(at: index)
                                save(times: next)
                            } label: {
                                Image(systemName: "minus.circle").font(.system(size: 18)).foregroundStyle(theme.secondaryLabel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if prefs.times.count < DogDailyPrefs.maxTimes {
                    Button {
                        save(times: prefs.times + [QuoteCopy.nextSuggestedTime(after: prefs.times)])
                    } label: {
                        Label("Another one, please", systemImage: "plus.circle")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                    }
                    .buttonStyle(.plain)
                }
                Text("Quiet hours in Settings still apply.").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    private func save(enabled: Bool? = nil, times: [String]? = nil) {
        let before = store.me.prefs
        var optimistic = before
        if let enabled { optimistic.enabled = enabled }
        if let times { optimistic.times = times }
        store.setPrefs(optimistic)
        saving = true
        Task { @MainActor in
            defer { saving = false }
            do {
                store.setPrefs(try await DogsClient(context: context).saveSettings(enabled: enabled, times: times))
                if enabled == true {
                    context.track("daily_dog_on")
                    if await context.host.notificationPermission() == .denied {
                        context.host.presentAlert(WidgetAlert(title: "Notifications are off",
                                                              message: "Turn on notifications for FavCircles in Settings to get your Daily Dog."))
                    }
                }
            } catch {
                store.setPrefs(before)
                context.host.presentAlert(WidgetAlert(title: "Couldn't save", message: DogErrors.message(error)))
            }
        }
    }
}

/// A Daily Dog as a card: the picture when it's a pup, the line otherwise.
struct DailyDogCard: View {
    let context: WidgetContext
    let item: DailyDog
    let big: Bool

    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(item.kind.emoji) \(item.kind.label)").font(.system(size: 13, weight: .bold)).foregroundStyle(big ? .white : context.accent)
                Spacer()
                if let date = DogDay.display(item.date, calendar: context.calendar) {
                    Text(date).font(.system(size: 12)).foregroundStyle(big ? .white.opacity(0.85) : theme.secondaryLabel)
                }
            }
            if let post = item.post {
                CachedRemoteImage(url: big ? post.displayURL : post.thumbnailURL) { $0.resizable().scaledToFill() } placeholder: {
                    theme.tertiaryBackground
                }
                .frame(maxWidth: .infinity).frame(height: big ? 260 : 140)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if !item.text.isEmpty {
                Text(item.text)
                    .font(.system(size: big ? 22 : 16, weight: big ? .heavy : .semibold, design: .rounded))
                    .foregroundStyle(big ? .white : theme.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let post = item.post, let names = post.dogNames {
                Text("🐶 \(names) · \(DogCopy.petted(post.petCount))")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(big ? .white.opacity(0.9) : theme.secondaryLabel)
            }
        }
        .padding(big ? 18 : 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(big ? AnyShapeStyle(LinearGradient(colors: [context.accent, Color(red: 0.95, green: 0.42, blue: 0.35)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(theme.secondaryBackground))
        )
    }
}

/// One Daily Dog full screen (the push lands here): Pet when it's a pup,
/// Share always.
struct DailyDogCover: View {
    let context: WidgetContext
    @ObservedObject var store: DogsStore
    @State var item: DailyDog
    let onClose: () -> Void
    @State private var burst = 0
    @State private var bounce = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [context.accent, Color(red: 0.95, green: 0.42, blue: 0.35)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    Text("\(item.kind.emoji) \(item.kind.label)").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 30)).foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                if let post = item.post {
                    ZStack {
                        DogPostMedia(post: post, theme: context.theme, height: 380, playsInline: true)
                            .onTapGesture(count: 2) { pet(post, fromDoubleTap: true) }
                        DogPawBurst(trigger: burst, accent: .white)
                    }
                } else {
                    Text("🐶").font(.system(size: 110))
                        .scaleEffect(bounce ? 1.08 : 0.94)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: bounce)
                        .onAppear { bounce = true }
                }
                if !item.text.isEmpty {
                    Text(item.text).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                if let names = item.post?.dogNames {
                    Text("🐶 \(names)").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                }
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    if let post = item.post {
                        Button { pet(post, fromDoubleTap: false) } label: {
                            Label(post.iPetted ? DogCopy.petted(post.petCount) : "Pet", systemImage: post.iPetted ? "pawprint.fill" : "pawprint")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Capsule().fill(.white))
                                .foregroundStyle(context.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    Button { share() } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Capsule().stroke(.white, lineWidth: 2))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .onAppear { context.track("daily_dog_opened", ["kind": item.kind.rawValue]) }
    }

    private func pet(_ post: DogPost, fromDoubleTap: Bool) {
        // A double tap only ever pets; the button toggles
        burst += post.iPetted ? (fromDoubleTap ? 1 : 0) : 1
        if fromDoubleTap && post.iPetted { context.host.haptic(.light); return }
        DogPetting.pet(post, store: store, context: context) { item.post = $0 }
    }

    private func share() {
        let item = item
        Task { @MainActor in
            let content = DogsWidget.shareCardContent(item, image: await DogShareImages.jpeg(item.post?.thumbnailURL))
            context.track("daily_dog_shared")
            context.host.share(WidgetShareKit.items(descriptor: context.descriptor, content: content))
        }
    }
}
