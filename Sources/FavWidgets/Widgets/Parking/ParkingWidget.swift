import SwiftUI
import MapKit
import FavWidgetsCore
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Parking Spot (Wes, 2026-10-08): "I parked here" saves the spot; then how
/// long ago, how far, walking directions, a note and photo, and a meter
/// timer that warns before it runs out.
public struct ParkingWidget: FavWidget {
    public init() {}

    public let descriptor = FavWidgetDescriptor(
        id: "parking",
        title: "Parking Spot",
        subtitle: "Remember where you parked",
        symbolName: "car.fill",
        accentHex: "#DD6B20",
        category: .health,
        schemaVersion: ParkingState.schemaVersion,
        shareBlurb: "Save where you parked, get walking directions back, and a meter reminder."
    )

    public func makeCardView(context: WidgetContext) -> AnyView {
        AnyView(ParkingCardView(context: context, state: context.state(ParkingState.self)))
    }

    public func makeFullView(context: WidgetContext) -> AnyView {
        AnyView(ParkingFullView(context: context, state: context.state(ParkingState.self)))
    }
}

/// Saving, clearing, the photo on disk and the meter notifications.
@MainActor
enum ParkingActions {
    static let notificationType = "parking_meter"

    static func park(context: WidgetContext, state: WidgetStateController<ParkingState>) async -> Bool {
        guard let here = await context.host.currentLocation() else { return false }
        let spot = ParkingSpot(latitude: here.latitude, longitude: here.longitude, savedAt: Date())
        clearPhoto()
        await clearReminders()
        state.update { $0.spot = spot }
        context.host.haptic(.success)
        context.track("parking_saved")
        let address = await reverse(here.latitude, here.longitude)
        if let address { state.update { $0.spot?.address = address } }
        return true
    }

    static func clear(context: WidgetContext, state: WidgetStateController<ParkingState>) {
        state.update { $0.spot = nil }
        clearPhoto()
        Task { await clearReminders() }
        context.track("parking_cleared")
    }

    static func setMeter(_ minutes: Int?, state: WidgetStateController<ParkingState>) {
        let ends = minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) }
        state.update { $0.spot?.meterEndsAt = ends }
        Task {
            await clearReminders()
            if let ends { await scheduleReminders(ends) }
        }
    }

    private static func reverse(_ lat: Double, _ lon: Double) async -> String? {
        let marks = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon))
        guard let m = marks?.first else { return nil }
        return [m.subThoroughfare.flatMap { n in m.thoroughfare.map { "\(n) \($0)" } } ?? m.thoroughfare ?? m.name, m.locality]
            .compactMap { $0 }.joined(separator: ", ")
    }

    private static func clearReminders() async {
        #if canImport(UserNotifications) && !os(macOS)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["parking-warn", "parking-expired"])
        #endif
    }

    private static func scheduleReminders(_ ends: Date) async {
        #if canImport(UserNotifications) && !os(macOS)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        for r in ParkingPlan.reminderTimes(meterEndsAt: ends, now: Date()) {
            let content = UNMutableNotificationContent()
            content.title = "🚗 Parking"
            content.body = r.text
            content.sound = .default
            content.userInfo = ["type": notificationType]
            let seconds = max(1, r.at.timeIntervalSinceNow)
            try? await center.add(UNNotificationRequest(identifier: r.id, content: content,
                                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
        }
        #endif
    }

    // MARK: Photo (this phone only)

    static var photoURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FavWidgets", isDirectory: true).appendingPathComponent("parking-photo.jpg")
    }

    static func savePhoto(_ jpeg: Data) {
        guard let url = photoURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? jpeg.write(to: url, options: .atomic)
    }

    static func clearPhoto() {
        if let url = photoURL { try? FileManager.default.removeItem(at: url) }
    }
}

struct ParkingCardView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<ParkingState>
    @State private var saving = false
    @State private var failed = false

    var body: some View {
        let theme = context.theme
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            WidgetCard(context: context, action: state.model.spot == nil
                       ? WidgetQuickAction(saving ? "Saving…" : "I parked here", symbolName: "mappin") { park() }
                       : WidgetQuickAction("Walk there", symbolName: "figure.walk") { walk() }) {
                if let spot = state.model.spot {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ParkingPlan.parkedText(spot.savedAt, now: timeline.date)).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                        Text([spot.note.isEmpty ? nil : spot.note, spot.address].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                        if let meter = ParkingPlan.meterText(spot.meterEndsAt, now: timeline.date) {
                            Label(meter, systemImage: "timer").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle((spot.meterEndsAt ?? .distantFuture) < timeline.date.addingTimeInterval(600) ? theme.danger : context.accent)
                        }
                    }
                } else {
                    WidgetUI.summary(failed ? "Couldn't get your location — check Location for FavCircles" : "Tap when you park so you can find your car later", theme: theme)
                }
            }
        }
        .task { await state.loadIfNeeded() }
    }

    private func park() {
        guard !saving else { return }
        saving = true
        Task { failed = !(await ParkingActions.park(context: context, state: state)); saving = false }
    }

    private func walk() {
        if let spot = state.model.spot, let url = ParkingPlan.walkURL(spot) { context.host.openURL(url) }
    }
}

struct ParkingFullView: View {
    let context: WidgetContext
    @ObservedObject var state: WidgetStateController<ParkingState>
    @State private var here: WidgetCoordinate?
    @State private var saving = false
    @State private var failed = false
    @State private var showCamera = false
    @State private var photo: PostcardPlatformImage?
    @State private var note = ""

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let spot = state.model.spot { saved(spot) } else { notSaved }
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .task {
            await state.loadIfNeeded()
            note = state.model.spot?.note ?? ""
            loadPhoto()
            here = await context.host.currentLocation()
        }
        #if os(iOS)
        .sheet(isPresented: $showCamera) { PostcardCameraPicker(image: $photo).ignoresSafeArea() }
        .onChange(of: photo) { image in
            guard let image, let jpeg = image.jpegData(compressionQuality: 0.6) else { return }
            ParkingActions.savePhoto(jpeg)
            state.update { $0.spot?.hasPhoto = true }
        }
        #endif
    }

    private var notSaved: some View {
        VStack(spacing: 14) {
            Image(systemName: "car.fill").font(.system(size: 46)).foregroundStyle(context.accent)
            Text("Park, then tap the button. We'll remember where.").font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
            WidgetUI.primaryButton(saving ? "Saving…" : "I parked here", color: context.accent) {
                guard !saving else { return }
                saving = true
                Task {
                    failed = !(await ParkingActions.park(context: context, state: state))
                    saving = false
                    here = await context.host.currentLocation()
                }
            }
            if failed {
                Text("Couldn't get your location. Turn on Location for FavCircles in Settings.")
                    .font(.system(size: 13)).foregroundStyle(theme.danger)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 30)
    }

    private func saved(_ spot: ParkingSpot) -> some View {
        let usesMetric = Locale.current.measurementSystem != .us
        return VStack(alignment: .leading, spacing: 14) {
            ParkingMap(spot: spot, here: here, accent: context.accent)
                .frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            TimelineView(.periodic(from: .now, by: 15)) { t in
                VStack(alignment: .leading, spacing: 4) {
                    Text(ParkingPlan.parkedText(spot.savedAt, now: t.date)).font(.system(size: 20, weight: .bold)).foregroundStyle(theme.label)
                    HStack(spacing: 8) {
                        if let address = spot.address { Text(address) }
                        if let here {
                            Text(ParkingPlan.distanceText(meters: ParkingPlan.distance((here.latitude, here.longitude), (spot.latitude, spot.longitude)),
                                                          usesMetric: usesMetric) + " away")
                        }
                    }
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                    if let meter = ParkingPlan.meterText(spot.meterEndsAt, now: t.date) {
                        Label(meter, systemImage: "timer").font(.system(size: 16, weight: .semibold)).foregroundStyle(context.accent)
                    }
                }
            }
            WidgetUI.primaryButton("Walk there", color: context.accent) {
                if let url = ParkingPlan.walkURL(spot) { context.host.openURL(url) }
            }
            TextField("Note (e.g. Level 3, row B)", text: $note)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                .onSubmit { state.update { $0.spot?.note = note } }
                .onChange(of: note) { value in state.update { $0.spot?.note = String(value.prefix(120)) } }
            meterRow(spot)
            photoRow(spot)
            Button("I'm back at my car — clear spot", role: .destructive) { ParkingActions.clear(context: context, state: state) }
                .font(.system(size: 14))
                .frame(maxWidth: .infinity)
            Text("Saved on your account; the photo stays on this phone.").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
        }
    }

    private func meterRow(_ spot: ParkingSpot) -> some View {
        Menu {
            ForEach([15, 30, 60, 90, 120, 180, 240], id: \.self) { m in
                Button(m < 60 ? "\(m) min" : "\(m / 60)h\(m % 60 == 0 ? "" : " \(m % 60)m")") {
                    ParkingActions.setMeter(m, state: state); context.track("parking_meter_set", ["minutes": "\(m)"])
                }
            }
            if spot.meterEndsAt != nil { Button("No meter", role: .destructive) { ParkingActions.setMeter(nil, state: state) } }
        } label: {
            Label(spot.meterEndsAt == nil ? "Set a meter timer" : "Change meter timer", systemImage: "timer")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
        }
    }

    @ViewBuilder
    private func photoRow(_ spot: ParkingSpot) -> some View {
        #if os(iOS)
        if let photo {
            Image(uiImage: photo).resizable().scaledToFill().frame(height: 200).frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        if PostcardCameraPicker.isAvailable {
            Button { showCamera = true } label: {
                Label(photo == nil ? "Take a photo of the spot" : "Retake photo", systemImage: "camera.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.label)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
            }
            .buttonStyle(.plain)
        }
        #endif
    }

    private func loadPhoto() {
        #if os(iOS)
        guard state.model.spot?.hasPhoto == true, let url = ParkingActions.photoURL,
              let data = try? Data(contentsOf: url) else { return }
        photo = UIImage(data: data)
        #endif
    }
}

/// The car (and you, when known).
struct ParkingMap: View {
    struct Pin: Identifiable { let id: String; let coordinate: CLLocationCoordinate2D; let isCar: Bool }
    let spot: ParkingSpot
    let here: WidgetCoordinate?
    let accent: Color
    @State private var region = MKCoordinateRegion()

    var body: some View {
        let pins = [Pin(id: "car", coordinate: .init(latitude: spot.latitude, longitude: spot.longitude), isCar: true)]
            + (here.map { [Pin(id: "me", coordinate: .init(latitude: $0.latitude, longitude: $0.longitude), isCar: false)] } ?? [])
        Map(coordinateRegion: $region, annotationItems: pins) { pin in
            MapAnnotation(coordinate: pin.coordinate) {
                if pin.isCar {
                    Image(systemName: "car.circle.fill").font(.system(size: 34)).foregroundStyle(.white, accent).shadow(radius: 3)
                } else {
                    Circle().fill(.blue).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .onAppear { region = fit(pins) }
        .onChange(of: here?.latitude) { _ in region = fit(pins) }
    }

    private func fit(_ pins: [Pin]) -> MKCoordinateRegion {
        let lats = pins.map(\.coordinate.latitude), lons = pins.map(\.coordinate.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.004, (lats.max()! - lats.min()!) * 1.6),
                                    longitudeDelta: max(0.004, (lons.max()! - lons.min()!) * 1.6))
        return MKCoordinateRegion(center: center, span: span)
    }
}
