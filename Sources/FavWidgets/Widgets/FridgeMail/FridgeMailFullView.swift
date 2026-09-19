import SwiftUI
import PhotosUI
import FavWidgetsCore

/// The whole of Fridge Mail on one screen: what goes out next, the queue
/// of drawings, the grandparents, the weekly schedule, how it's paid for,
/// and what has already been mailed.
struct FridgeMailFullView: View {
    let context: WidgetContext
    @ObservedObject var store: FridgeMailStore

    @State var photoItem: PhotosPickerItem?
    @State var showCamera = false
    @State var pickedImage: PostcardPlatformImage?
    @State var showAddSheet = false
    @State var recipientSheet: RecipientSheet?
    /// Which button is mid-flight, so the rest stay tappable but that one
    /// can't be double-tapped.
    @State var busy: String?
    @State var familyNameDraft = ""

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let plan = store.plan {
                    if plan.isEmpty { explainer }
                    nextCard(plan)
                    queueSection(plan)
                    recipientsSection(plan)
                    scheduleSection(plan)
                    planSection(plan)
                    sentSection
                } else if let error = store.loadError {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).font(.system(size: 14)).foregroundStyle(theme.danger)
                        Button("Try again") { Task { await store.load(context: context) } }
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading your Fridge Mail…").font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                    }
                }
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle("Fridge Mail")
        .task {
            await store.loadIfNeeded(context: context)
            await store.loadDetails(context: context)
            familyNameDraft = store.plan?.familyName ?? ""
        }
        .onChange(of: store.plan?.familyName) { name in
            if let name, familyNameDraft.isEmpty { familyNameDraft = name }
        }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task { await loadPhoto(from: item) }
        }
        .onChange(of: pickedImage) { image in
            if image != nil { showAddSheet = true }
        }
        .widgetCameraCover(isPresented: $showCamera) {
            #if os(iOS)
            PostcardCameraPicker(image: $pickedImage).ignoresSafeArea()
            #endif
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { pickedImage = nil; photoItem = nil }) {
            if let image = pickedImage {
                FridgeMailAddSheet(context: context, store: store, image: image)
            }
        }
        .sheet(item: $recipientSheet) { item in
            FridgeMailRecipientSheet(context: context, store: store, editing: item.recipient)
        }
    }

    /// Which grandparent sheet is up: a blank one, or one filled in for editing.
    struct RecipientSheet: Identifiable {
        let recipient: FridgeMailRecipient?
        var id: String { recipient?.id ?? "new" }
        static let add = RecipientSheet(recipient: nil)
    }

    // MARK: - Explainer

    var explainer: some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 10) {
            Text("Every week, a real postcard of your kid's latest drawing lands in Grandma's mailbox. You add the drawings; we print and mail them.")
                .font(.system(size: 15))
                .foregroundStyle(theme.label)
                .fixedSize(horizontal: false, vertical: true)
            step(1, "Add a grandparent", "Name and address. Up to three.")
            step(2, "Add drawings", "Snap them with the camera or pick from your photos. Add a few so there's always one waiting.")
            step(3, "We mail one a week", "Printed on a 4×6 postcard with the child's name, the date and your note on the back.")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FridgeMailCanvasView.cream))
    }

    func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(context.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(FridgeMailCanvasView.ink)
                Text(detail).font(.system(size: 12)).foregroundStyle(FridgeMailCanvasView.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Next card

    // MARK: - Queue

    // MARK: - Recipients

    // MARK: - Schedule

    // MARK: - Plan (money)

    // MARK: - Sent

    // MARK: - Actions

}

// MARK: - Pieces

