import SwiftUI
import FavWidgetsCore
#if canImport(CoreImage)
import CoreImage
import CoreImage.CIFilterBuiltins
#endif
#if os(iOS)
import UIKit
#endif

/// Wi-Fi Here (Wes, 2026-11-20): the network and password for the places you
/// go back to. When you're there, the card shows it; a QR lets a guest's
/// camera join in one scan. Nothing to type twice, nothing to ask for.
public struct WiFiHereWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "wifihere",
        title: "Wi-Fi Here",
        subtitle: "The password for wherever you are",
        symbolName: "wifi",
        accentHex: "#2B6CB0",
        category: .social,
        schemaVersion: WiFiSpotList.schemaVersion,
        shareBlurb: "Save the Wi-Fi at the places you go back to; it shows up when you're there, with a QR for guests."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(WiFiCardView(context: context, state: context.state(WiFiSpotList.self)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(WiFiFullView(context: context, state: context.state(WiFiSpotList.self)))
    }
}

@MainActor
enum WiFiActions {
    static func copy(_ text: String, context: WidgetContext) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #endif
        context.host.haptic(.success)
        context.track("wifi_copied")
    }

    static func markUsed(_ spot: WiFiSpot, state: WidgetStateController<WiFiSpotList>) {
        state.update { list in
            guard let i = list.spots.firstIndex(where: { $0.id == spot.id }) else { return }
            list.spots[i].lastUsedAt = Date()
        }
    }

    /// Where I am, as the nearest of my saved places (the app host's own
    /// "current place" lookup is empty, so this does the work).
    static func nearbyPlaces(context: WidgetContext, at location: WidgetCoordinate) async -> [WidgetPlaceCandidate] {
        let found = try? await context.host.fetchPlaces(WidgetPlaceQuery(sources: [.mine], near: location, radiusMeters: 400))
        return (found ?? []).sorted { $0.coordinate.distance(to: location) < $1.coordinate.distance(to: location) }
    }

    /// The standard Wi-Fi QR, drawn at `side` points.
    static func qrImage(network: String, password: String, side: CGFloat) -> PostcardPlatformImage? {
        #if canImport(CoreImage) && os(iOS)
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(WiFiPlan.qrPayload(network: network, password: password).utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = side * 3 / max(output.extent.width, 1)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
        #else
        return nil
        #endif
    }
}

struct WiFiCardView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<WiFiSpotList>
    @State private var location: WidgetCoordinate?
    @State private var revealed = false

    var body: some View {
        let theme = context.theme
        let here = WiFiPlan.here(state.model.spots, at: location)
        WidgetCard(context: context, action: here.map { spot in
            WidgetQuickAction("Copy", symbolName: "doc.on.doc") {
                WiFiActions.copy(spot.password.isEmpty ? spot.network : spot.password, context: context)
                WiFiActions.markUsed(spot, state: state)
            }
        } ?? WidgetQuickAction("Add", symbolName: "plus") { context.openFullView() }) {
            if let spot = here {
                VStack(alignment: .leading, spacing: 3) {
                    Text("You're at \(spot.placeName)").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                    Text(spot.network).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label).lineLimit(1)
                    Button { revealed.toggle() } label: {
                        Text(revealed || spot.isOpenNetwork ? (spot.isOpenNetwork ? "Open network" : spot.password) : WiFiPlan.masked(spot.password))
                            .font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(context.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealed ? "Hide password" : "Show password")
                }
            } else if state.model.spots.isEmpty {
                WidgetUI.summary("Save the Wi-Fi where you are — it shows up next time you're here", theme: theme)
            } else {
                let n = state.model.spots.count
                WidgetUI.summary(n == 1 ? "1 place saved · not here right now" : "\(n) places saved · not at one right now", theme: theme)
            }
        }
        .task {
            await state.loadIfNeeded()
            location = await context.host.currentLocation()
        }
    }
}

struct WiFiFullView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<WiFiSpotList>
    @State private var location: WidgetCoordinate?
    @State private var adding = false
    @State private var showing: WiFiSpot?
    @State private var editing: WiFiSpot?

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        let here = WiFiPlan.here(state.model.spots, at: location)
        let ordered = WiFiPlan.sorted(state.model.spots, near: location)
        List {
            if let here {
                Section("You're here") { row(here, isHere: true) }
            }
            Section {
                Button { adding = true } label: {
                    Label(here == nil ? "Save the Wi-Fi where I am" : "Save another place's Wi-Fi", systemImage: "plus.circle.fill")
                        .foregroundStyle(context.accent)
                }
            }
            Section(ordered.isEmpty ? "" : "Saved places") {
                if ordered.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dad's house, the cabin, your favorite café.").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                        Text("Save a network once. Next time you're there, the password is on the card — and a QR lets a guest join in one scan.")
                            .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                    }
                    .padding(.vertical, 6)
                }
                ForEach(ordered.filter { $0.id != here?.id }) { spot in row(spot, isHere: false) }
            }
            Section {
                Text("Saved on your account, so a new phone has them too. Only you see them.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .task {
            await state.loadIfNeeded()
            location = await context.host.currentLocation()
        }
        .sheet(isPresented: $adding) { WiFiEditSheet(context: context, state: state, editing: nil, location: location) }
        .sheet(item: $editing) { spot in WiFiEditSheet(context: context, state: state, editing: spot, location: location) }
        .sheet(item: $showing) { spot in WiFiShowSheet(context: context, state: state, spot: spot) }
    }

    private func row(_ spot: WiFiSpot, isHere: Bool) -> some View {
        Button { showing = spot; WiFiActions.markUsed(spot, state: state) } label: {
            HStack(spacing: 12) {
                Image(systemName: isHere ? "wifi" : "wifi")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(isHere ? .white : context.accent)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isHere ? context.accent : context.accent.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(spot.placeName).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label).lineLimit(1)
                    Text("\(spot.network) · \(WiFiPlan.masked(spot.password))").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                }
                Spacer()
                Image(systemName: "qrcode").foregroundStyle(theme.secondaryLabel)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Edit") { editing = spot }.tint(.gray)
        }
    }
}

/// The network, the password in the clear, Copy, and the QR a guest scans.
struct WiFiShowSheet: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<WiFiSpotList>
    let spot: WiFiSpot
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        WidgetSheet(title: spot.placeName, theme: theme) {
            ScrollView {
                VStack(spacing: 18) {
                    if let qr = WiFiActions.qrImage(network: spot.network, password: spot.password, side: 220) {
                        VStack(spacing: 8) {
                            #if os(iOS)
                            Image(uiImage: qr).interpolation(.none).resizable().frame(width: 220, height: 220)
                                .padding(12).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
                            #endif
                            Text("Point a phone's camera here to join").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                        }
                    }
                    VStack(spacing: 6) {
                        Text(spot.network).font(.system(size: 22, weight: .bold)).foregroundStyle(theme.label)
                        Text(spot.isOpenNetwork ? "Open network — no password" : spot.password)
                            .font(.system(size: 20, weight: .semibold, design: .monospaced)).foregroundStyle(context.accent)
                            .textSelection(.enabled)
                        if !spot.note.isEmpty { Text(spot.note).font(.system(size: 14)).foregroundStyle(theme.secondaryLabel) }
                    }
                    if !spot.isOpenNetwork {
                        WidgetUI.primaryButton(copied ? "Copied" : "Copy password", color: context.accent) {
                            WiFiActions.copy(spot.password, context: context)
                            copied = true
                        }
                    }
                }
                .padding(20)
            }
        }
    }
}

/// Add or edit: where (the place you're at, or any of your saved places, or
/// a typed name), the network and the password.
struct WiFiEditSheet: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<WiFiSpotList>
    let editing: WiFiSpot?
    let location: WidgetCoordinate?
    @Environment(\.dismiss) private var dismiss
    @State private var placeName = ""
    @State private var placeId: String?
    @State private var coordinate: WidgetCoordinate?
    @State private var network = ""
    @State private var password = ""
    @State private var note = ""
    @State private var nearby: [WidgetPlaceCandidate] = []
    @State private var searched: [WidgetPlaceCandidate] = []
    @State private var placeQuery = ""
    @State private var confirmDelete = false

    private var theme: WidgetTheme { context.theme }
    private var canSave: Bool { !placeName.trimmingCharacters(in: .whitespaces).isEmpty && !network.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        WidgetSheet(title: editing == nil ? "Save Wi-Fi" : "Edit Wi-Fi", theme: theme, confirm: ("Save", canSave, save)) {
            Form {
                Section("Where") {
                    TextField("Place (e.g. Dad's house)", text: $placeName)
                        .onChange(of: placeName) { value in
                            // Typing a new name detaches it from a picked place
                            if let picked = (nearby + searched).first(where: { $0.id == placeId }), picked.name != value {
                                placeId = nil
                            }
                            placeQuery = value
                        }
                    if !nearby.isEmpty || !searched.isEmpty {
                        ForEach(Array((placeQuery.isEmpty ? nearby : searched).prefix(5))) { place in
                            Button {
                                placeName = place.name; placeId = place.id; coordinate = place.coordinate; placeQuery = ""
                            } label: {
                                HStack {
                                    Image(systemName: placeId == place.id ? "checkmark.circle.fill" : "mappin.circle")
                                        .foregroundStyle(placeId == place.id ? context.accent : theme.secondaryLabel)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(place.name).foregroundStyle(theme.label)
                                        if let address = place.address { Text(address).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).lineLimit(1) }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if coordinate == nil, location != nil {
                        Button { coordinate = location; if placeName.isEmpty { placeName = "Here" } } label: {
                            Label("Use my current location", systemImage: "location.fill")
                        }
                    } else if coordinate != nil, placeId == nil {
                        Text("Pinned to where you are now.").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                }
                Section("Network") {
                    TextField("Network name", text: $network).autocorrectionDisabled()
                    TextField("Password (leave empty for an open network)", text: $password).autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("Note (e.g. router is in the hall closet)", text: $note)
                }
                if editing != nil {
                    Section { Button("Delete this Wi-Fi", role: .destructive) { confirmDelete = true } }
                }
            }
            .task {
                if let e = editing {
                    placeName = e.placeName; placeId = e.placeId; coordinate = e.coordinate
                    network = e.network; password = e.password; note = e.note
                }
                if let location {
                    nearby = await WiFiActions.nearbyPlaces(context: context, at: location)
                    if editing == nil, let first = WiFiPlan.nearestPlace(nearby, to: location) {
                        placeName = first.name; placeId = first.id; coordinate = first.coordinate
                    } else if editing == nil { coordinate = location }
                }
            }
            .task(id: placeQuery) {
                let q = placeQuery.trimmingCharacters(in: .whitespaces)
                guard q.count >= 2 else { searched = []; return }
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                let mine = (try? await context.host.fetchPlaces(WidgetPlaceQuery(sources: [.mine], near: location, radiusMeters: 500_000))) ?? []
                searched = mine.filter { $0.name.localizedCaseInsensitiveContains(q) }
            }
            .confirmationDialog("Delete the Wi-Fi for \(placeName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let e = editing { state.update { $0.spots.removeAll { $0.id == e.id } } }
                    dismiss()
                }
            }
        }
    }

    private func save() {
        let name = placeName.trimmingCharacters(in: .whitespaces)
        let ssid = network.trimmingCharacters(in: .whitespaces)
        state.update { list in
            if let e = editing, let i = list.spots.firstIndex(where: { $0.id == e.id }) {
                list.spots[i].placeName = name; list.spots[i].placeId = placeId; list.spots[i].coordinate = coordinate
                list.spots[i].network = ssid; list.spots[i].password = password; list.spots[i].note = note
                list.spots[i].updatedAt = Date()
            } else {
                list.spots.append(WiFiSpot(placeName: name, placeId: placeId, coordinate: coordinate, network: ssid, password: password, note: note))
            }
        }
        context.track(editing == nil ? "wifi_saved" : "wifi_edited")
        dismiss()
    }
}
