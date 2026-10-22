import SwiftUI
import FavWidgetsCore

enum DogsTab: String, CaseIterable, Identifiable {
    case park, daily, mine
    var id: String { rawValue }
    var label: String {
        switch self {
        case .park: return "Dog Park"
        case .daily: return "Daily Dog"
        case .mine: return "My Dogs"
        }
    }
}

/// The widget's page: the welcome until you join, then the three tabs.
/// Links and pushes land here (a post, a Daily Dog).
struct DogsFullView: View {
    let context: WidgetContext
    @ObservedObject var store: DogsStore
    @ObservedObject var state: WidgetStateController<DogsState>

    @State private var tab: DogsTab = .park
    @State private var openPost: DogPost?
    @State private var openDaily: DailyDog?
    @State private var addingDog = false
    @State private var joining = false

    var body: some View {
        let theme = context.theme
        VStack(spacing: 0) {
            WidgetSyncBadge(state: state.syncState, theme: theme)
            if !store.hasLoaded {
                if let error = store.loadError {
                    retry(error, theme: theme)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if !store.me.minVersionOk {
                updateNeeded(theme)
            } else if !store.me.member {
                DogsWelcomeView(context: context, busy: joining, onJoin: join)
            } else {
                Picker("", selection: $tab) {
                    ForEach(DogsTab.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
                switch tab {
                case .park:
                    DogParkView(context: context, store: store, onOpen: { openPost = $0 }, onAddDog: { addingDog = true })
                case .daily:
                    DailyDogTab(context: context, store: store, onOpen: { openDaily = $0 })
                case .mine:
                    MyDogsView(context: context, store: store, state: state, onAddDog: { addingDog = true },
                               onOpenPost: { openPost = $0 })
                }
            }
        }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .task {
            await store.refresh(context)
            await state.loadIfNeeded()
            await DogReminderScheduler.sync(dogs: store.me.dogs, state: state.model, quietHours: context.host.quietHours)
        }
        .task { await openLaunched() }
        .onChange(of: state.model) { model in
            Task { await DogReminderScheduler.sync(dogs: store.me.dogs, state: model, quietHours: context.host.quietHours) }
        }
        .onChange(of: store.me.dogs) { dogs in
            Task { await DogReminderScheduler.sync(dogs: dogs, state: state.model, quietHours: context.host.quietHours) }
        }
        .sheet(item: $openPost) { post in
            DogPostDetailView(context: context, store: store, post: post) { openPost = nil }
        }
        .sheet(isPresented: $addingDog) {
            DogEditSheet(context: context, dog: nil) { dog in
                store.upsertDog(dog)
                tab = .mine
            }
        }
        .fullScreenCoverOrSheet(item: $openDaily) { item in
            DailyDogCover(context: context, store: store, item: item) { openDaily = nil }
        }
    }

    private func retry(_ error: String, theme: WidgetTheme) -> some View {
        VStack(spacing: 12) {
            Text("🐶").font(.system(size: 54))
            Text(error).font(.system(size: 15)).foregroundStyle(theme.secondaryLabel).multilineTextAlignment(.center)
            Button("Try again") { Task { await store.refresh(context, force: true) } }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func updateNeeded(_ theme: WidgetTheme) -> some View {
        VStack(spacing: 12) {
            Text("🐕‍🦺").font(.system(size: 64))
            Text("Update FavCircles to join the Dog Park").font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(theme.label).multilineTextAlignment(.center)
            Text("The newest version has Can I Pet Dat Dog. Update in the App Store, then come back for the pups.")
                .font(.system(size: 15)).foregroundStyle(theme.secondaryLabel).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Both doors join the Dog Park; "Add your dog" then opens the dog form.
    private func join(addDog: Bool) {
        guard !joining else { return }
        joining = true
        Task { @MainActor in
            defer { joining = false }
            do {
                try await DogsClient(context: context).join()
                store.setMember(true)
                context.host.haptic(.success)
                context.track("dogs_joined", ["withDog": addDog ? "1" : "0"])
                await store.refresh(context, force: true)
                if addDog {
                    await context.waitForPageToSettle()
                    addingDog = true
                }
            } catch {
                context.host.presentAlert(WidgetAlert(title: "Couldn't join the Dog Park", message: DogErrors.message(error)))
            }
        }
    }

    /// A post or a Daily Dog from a link or push. Read once and cleared.
    private func openLaunched() async {
        let client = DogsClient(context: context)
        if let id = context.launchDogPostId {
            context.launchDogPostId = nil
            await context.waitForPageToSettle()
            do { openPost = try await client.post(id) } catch {
                context.host.presentAlert(WidgetAlert(title: "That post is gone", message: "It may have been deleted. There are plenty more good dogs in the Dog Park."))
            }
        } else if let id = context.launchDailyDogId {
            context.launchDailyDogId = nil
            tab = .daily
            await context.waitForPageToSettle()
            do { openDaily = try await client.dailyItem(id) } catch {
                if let today = store.me.today { openDaily = today }
            }
        }
    }
}

/// The first open: what it is, and two ways in.
struct DogsWelcomeView: View {
    let context: WidgetContext
    let busy: Bool
    let onJoin: (_ addDog: Bool) -> Void
    @State private var wiggle = false

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(spacing: 18) {
                Text("🐶").font(.system(size: 96))
                    .rotationEffect(.degrees(wiggle ? -8 : 8))
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: wiggle)
                    .onAppear { wiggle = true }
                Text("Can I pet dat dog?").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(theme.label)
                Text("A happy place for dog people.").font(.system(size: 17)).foregroundStyle(theme.secondaryLabel)
                VStack(alignment: .leading, spacing: 12) {
                    feature("📸", "The Dog Park", "Post your pup, pet everyone else's. Photos and 15-second clips.")
                    feature("😂", "Daily Dog", "A funny dog thing every day, at the time you pick.")
                    feature("🩺", "My Dogs", "Vaccines, vet, insurance and favorite dog spots. Private to you.")
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.secondaryBackground))
                WidgetUI.primaryButton(busy ? "Joining…" : "🐾 Add your dog", color: context.accent) { onJoin(true) }
                    .disabled(busy)
                Button { onJoin(false) } label: {
                    Text("Just here for the dogs").font(.system(size: 16, weight: .semibold)).foregroundStyle(context.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(busy)
                Text("Joining shows your name and photo on what you post. Your dog's health and insurance are never shared.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }

    private func feature(_ emoji: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(context.theme.label)
                Text(text).font(.system(size: 13)).foregroundStyle(context.theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
